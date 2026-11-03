import AppKit
@preconcurrency import ApplicationServices

/// Applies window commands over AX. See docs/features/window-management.md#applying-a-placement.
@MainActor
final class WindowMover {
    /// `CFEqual`/`CFHash` are the supported identity; the pid separates two processes' elements.
    private struct ExternalKey: Hashable {
        let pid: pid_t
        let element: AXUIElement

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(pid)
            hasher.combine(CFHash(element))
        }
    }

    /// A closed window's identifier can be reused; `decide` rejects the stale record on its frame.
    private enum WindowKey: Hashable {
        case external(ExternalKey)
        case own(ObjectIdentifier)
    }

    /// One of ours or another app's: an AX call into our own process would stall the main thread.
    @MainActor
    private enum Surface {
        case external(application: AXUIElement, window: AXUIElement)
        case own(NSWindow)

        var isFullScreen: Bool { fullScreenState == true }

        var fullScreenState: Bool? {
            switch self {
            case .external(_, let window): AXWindowAccess.fullScreenState(window)
            case .own(let window): window.styleMask.contains(.fullScreen)
            }
        }

        var canMove: Bool {
            switch self {
            case .external(_, let window):
                AXWindowAccess.isSettable(kAXPositionAttribute, on: window)
            case .own(let window): window.isMovable
            }
        }

        var canResize: Bool {
            switch self {
            case .external(_, let window):
                AXWindowAccess.isSettable(kAXSizeAttribute, on: window)
            case .own(let window): window.styleMask.contains(.resizable)
            }
        }

        func frame(in geometry: AXGeometry) -> CGRect? {
            switch self {
            case .external(_, let window): AXWindowAccess.frame(of: window)
            case .own(let window): geometry.flip(window.frame)
            }
        }

        /// Our own windows answer locally, with no messaging round trip to bound.
        func setMessagingTimeout(_ seconds: Float) {
            guard case .external(_, let window) = self else { return }
            AXUIElementSetMessagingTimeout(window, seconds)
        }

        /// Nothing to suppress on our own windows: it is a remote app's Accessibility setting.
        func suppressEnhancedUserInterface() -> () -> Void {
            guard case .external(let application, _) = self else { return {} }
            return AXWindowAccess.suppressEnhancedUserInterface(on: application)
        }

        func write(
            _ placement: WindowPlacementEngine.Placement, current: CGRect, canResize: Bool,
            canvas: CGRect?, geometry: AXGeometry
        ) -> CGRect? {
            switch self {
            case .external(_, let window):
                AXWindowAccess.write(
                    placement.frame, anchor: placement.anchor, to: window, current: current,
                    canResize: canResize, canvas: canvas)
            case .own(let window):
                Self.writeOwn(
                    placement, to: window, current: current, canResize: canResize,
                    canvas: canvas, geometry: geometry)
            }
        }

        /// `setFrame` is atomic and local, so AX's size → position → size sequence buys nothing.
        private static func writeOwn(
            _ placement: WindowPlacementEngine.Placement, to window: NSWindow, current: CGRect,
            canResize: Bool, canvas: CGRect?, geometry: AXGeometry
        ) -> CGRect? {
            var target =
                canResize
                ? placement.frame : placement.anchor.place(current.size, in: placement.frame)
            if !canResize, let canvas {
                target = WindowPlacementEngine.clamped(target, into: canvas)
            }
            window.setFrame(geometry.flip(WindowPlacementEngine.rounded(target)), display: true)
            var actual = geometry.flip(window.frame)

            // `contentMinSize` can refuse the width or height; re-seat once, per the anchor.
            if actual.width > target.width + AXWindowAccess.clampTolerance
                || actual.height > target.height + AXWindowAccess.clampTolerance
            {
                var slot = placement.anchor.place(actual.size, in: placement.frame)
                if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
                window.setFrameOrigin(geometry.flip(WindowPlacementEngine.rounded(slot)).origin)
                actual = geometry.flip(window.frame)
            }
            return actual
        }
    }

    /// The frame and displays one placement reads, taken again once a window leaves fullscreen.
    @MainActor
    private struct Snapshot {
        let geometry: AXGeometry
        let frame: CGRect
        let screens: [WindowPlacementEngine.Screen]

        init?(of surface: Surface) {
            let geometry = AXGeometry(screens: NSScreen.screens)
            guard let frame = surface.frame(in: geometry) else { return nil }
            self.geometry = geometry
            self.frame = frame
            screens = AXScreens.converted(NSScreen.screens, geometry: geometry)
        }
    }

    private var memory = WindowActionMemory<WindowKey>()
    /// At most one per window; a newer command on that window cancels it.
    private var fullScreenTransitions: [WindowKey: Task<Void, Never>] = [:]
    private var terminationToken: NotificationToken?
    private var windowCloseToken: NotificationToken?

    init() {
        // Drop a quit app's windows rather than waiting for LRU eviction to reclaim them.
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.memory.forget { key in
                    guard case .external(let external) = key else { return false }
                    return external.pid == pid
                }
            }
        }
        terminationToken = NotificationToken(token, center: NSWorkspace.shared.notificationCenter)

        // A closed window's identifier can be reused, so drop its record while it is still ours.
        let closeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let closed = note.object as? NSWindow else { return }
            let key = WindowKey.own(ObjectIdentifier(closed))
            Task { @MainActor [weak self] in self?.memory.forget(key: key) }
        }
        windowCloseToken = NotificationToken(closeToken, center: .default)
    }

    /// The window a command targets, resolved once per press.
    private struct FocusedWindow {
        let surface: Surface
        let key: WindowKey
    }

    private typealias Resolver = (
        _ current: CGRect, _ screens: [WindowPlacementEngine.Screen],
        _ decision: WindowActionMemory<WindowKey>.Decision
    ) -> WindowPlacementEngine.Placement?

    /// Runs `command` against `target`'s focused window, returning whether anything changed.
    @discardableResult
    func perform(
        _ command: WindowCommand.ID, target: WindowTarget?, gap: CGFloat, cycle: WindowCycle,
        wrapsDisplays: Bool, keepsProportions: Bool
    ) -> Bool {
        guard let catalogued = WindowCommandCatalog.command(id: command),
            let focused = focusedWindow(of: target)
        else { return false }
        fullScreenTransitions.removeValue(forKey: focused.key)?.cancel()

        if catalogued.kind == .fullscreen {
            let entering = !focused.surface.isFullScreen
            guard requestFullScreen(entering, on: focused.surface) != nil else { return false }
            // The size chain is moot, but the pre-Tinycast frame is still the Restore target.
            memory.forgetCycle(key: focused.key, isFullScreen: entering)
            return true
        }
        return place(
            focused, command: command, gap: gap,
            reentersFullScreen: command == .nextDisplay || command == .previousDisplay,
            cycleLength: {
                WindowPlacementEngine.cycleLength(for: command, screens: $0, cycle: cycle)
            }
        ) { current, screens, decision in
            WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: command, windowFrame: current, screens: screens, gap: gap,
                    step: decision.step, cycle: cycle, originScreenID: decision.originScreenID,
                    restoreFrame: decision.canRestore ? decision.restoreFrame : nil,
                    lastTileCommand: decision.lastTileCommand, wrapsDisplays: wrapsDisplays,
                    keepsProportions: keepsProportions))
        }
    }

    /// Applies `size` to `target`'s focused window; Restore undoes it like any command.
    @discardableResult
    func perform(_ size: CustomWindowSize, target: WindowTarget?, gap: CGFloat) -> Bool {
        guard let focused = focusedWindow(of: target) else { return false }
        fullScreenTransitions.removeValue(forKey: focused.key)?.cancel()
        return place(
            focused, command: nil, gap: gap, reentersFullScreen: false, cycleLength: { _ in 1 },
            resolve: { current, screens, _ in
                size.placement(for: current, screens: screens, gap: gap)
            })
    }

    private func focusedWindow(of target: WindowTarget?) -> FocusedWindow? {
        switch target {
        case .own(let window):
            // No Accessibility grant is involved in placing one of our own windows.
            guard window.isVisible else { return nil }
            return FocusedWindow(surface: .own(window), key: .own(ObjectIdentifier(window)))
        case .external(let app):
            // Invoked from an explicit user gesture, so prompting for the grant is right here.
            guard Permissions.ensureAccessibility() else { return nil }
            guard !app.isTerminated,
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return nil }

            let application = AXWindowAccess.application(for: app.processIdentifier)
            guard let window = AXWindowAccess.targetWindow(in: application) else { return nil }
            AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
            return FocusedWindow(
                surface: .external(application: application, window: window),
                key: .external(ExternalKey(pid: app.processIdentifier, element: window)))
        case nil:
            return nil
        }
    }

    /// The one decide → resolve → write → commit sequence every geometry press runs through.
    private func place(
        _ focused: FocusedWindow, command: WindowCommand.ID?, gap: CGFloat,
        reentersFullScreen: Bool,
        cycleLength: ([WindowPlacementEngine.Screen]) -> Int, resolve: @escaping Resolver
    ) -> Bool {
        let surface = focused.surface
        guard let snapshot = Snapshot(of: surface),
            let host = WindowPlacementEngine.screen(containing: snapshot.frame, in: snapshot.screens)
        else { return false }

        let isFullScreen = surface.isFullScreen
        // One timestamp for the whole command, so the cycle timeout can't straddle two readings.
        let now = Date()
        var decision = memory.decide(
            key: focused.key, command: command, currentFrame: snapshot.frame,
            currentScreenID: host.id, cycleLength: cycleLength(snapshot.screens), now: now,
            isFullScreen: isFullScreen)
        // Whatever chain led here, Restore after leaving fullscreen goes back into it.
        if isFullScreen, command != .restore { decision.restoresFullScreen = true }

        if command == .restore, decision.canRestore, decision.restoresFullScreen {
            guard !isFullScreen, requestFullScreen(true, on: surface) != nil else { return false }
            memory.commit(
                key: focused.key, command: command, decision: decision,
                appliedFrame: snapshot.frame, screenID: host.id, now: now, appliedFullScreen: true)
            return true
        }
        guard isFullScreen else {
            return apply(
                focused, command: command, gap: gap, decision: decision, snapshot: snapshot,
                now: now, endsFullScreen: false, resolve: resolve)
        }

        // Resolved first, so a command with nowhere to go never takes the window out of fullscreen.
        guard resolve(snapshot.frame, snapshot.screens, decision) != nil else { return false }
        return leaveFullScreen(focused, reentering: reentersFullScreen) {
            guard let settled = Snapshot(of: surface) else { return }
            _ = self.apply(
                focused, command: command, gap: gap, decision: decision, snapshot: settled,
                now: now, endsFullScreen: reentersFullScreen, resolve: resolve)
        }
    }

    private func apply(
        _ focused: FocusedWindow, command: WindowCommand.ID?, gap: CGFloat,
        decision: WindowActionMemory<WindowKey>.Decision, snapshot: Snapshot, now: Date,
        endsFullScreen: Bool, resolve: Resolver
    ) -> Bool {
        let surface = focused.surface
        let current = snapshot.frame
        let screens = snapshot.screens
        guard let placement = resolve(current, screens, decision) else { return false }

        // Checked before any write, so an unpositionable window is left untouched.
        guard surface.canMove else { return false }
        let canResize = placement.resizes && surface.canResize

        let destination = screens.first { $0.id == placement.screenID }
        let canvas = destination.map {
            WindowPlacementEngine.canvas(
                $0.visibleFrame,
                gap: WindowPlacementEngine.sanitizedGap(gap, in: $0.visibleFrame))
        }
        let restoreEnhancedUI = canResize ? surface.suppressEnhancedUserInterface() : {}
        defer { restoreEnhancedUI() }

        guard
            let applied = surface.write(
                placement, current: current, canResize: canResize, canvas: canvas,
                geometry: snapshot.geometry)
        else { return false }

        let landedOn =
            WindowPlacementEngine.screen(containing: applied, in: screens)?.id
            ?? placement.screenID
        memory.commit(
            key: focused.key, command: command, decision: decision, appliedFrame: applied,
            screenID: landedOn, now: now, appliedFullScreen: endsFullScreen)
        return !applied.equalTo(current)
    }

    // MARK: - Fullscreen

    /// A failed `AXFullScreen` write may still flip the window, so only it needs confirming.
    private enum FullScreenRequest { case sent, unconfirmed }

    /// Outlasts the system exit animation, before which some apps undo a frame write.
    private static let fullScreenSettleDelay = Duration.milliseconds(750)
    private static let fullScreenPollInterval = Duration.milliseconds(100)
    private static let fullScreenTimeout = Duration.seconds(2)
    /// An app mid-animation answers slowly; each poll must not stall main for the full second.
    private static let fullScreenPollMessagingTimeout: Float = 0.5

    /// Places once the window is out of fullscreen. docs/features/window-management.md
    private func leaveFullScreen(
        _ focused: FocusedWindow, reentering: Bool, then place: @escaping () -> Void
    ) -> Bool {
        let surface = focused.surface
        guard let request = requestFullScreen(false, on: surface) else { return false }
        fullScreenTransitions[focused.key] = Task {
            // Once cancelled, the entry belongs to whichever command superseded this one.
            defer { if !Task.isCancelled { fullScreenTransitions[focused.key] = nil } }
            guard await confirm(request, on: surface, isFullScreen: false) else { return }
            do { try await Task.sleep(for: Self.fullScreenSettleDelay) } catch { return }
            place()
            if reentering { _ = requestFullScreen(true, on: surface) }
        }
        return true
    }

    /// False on timeout, or when a newer command on the window cancelled the wait.
    private func confirm(
        _ request: FullScreenRequest, on surface: Surface, isFullScreen wanted: Bool
    ) async -> Bool {
        guard request == .unconfirmed else { return true }
        surface.setMessagingTimeout(Self.fullScreenPollMessagingTimeout)
        defer { surface.setMessagingTimeout(AXWindowAccess.messagingTimeout) }
        let deadline = ContinuousClock.now + Self.fullScreenTimeout
        while ContinuousClock.now < deadline {
            // An unanswered read means not yet, never that the window changed state.
            if surface.fullScreenState == wanted { return true }
            do { try await Task.sleep(for: Self.fullScreenPollInterval) } catch { return false }
        }
        return false
    }

    /// `AXFullScreen`, then the green button. docs/features/window-management.md
    private func requestFullScreen(_ wanted: Bool, on surface: Surface) -> FullScreenRequest? {
        switch surface {
        case .own(let window):
            // AppKit fullscreens any resizable window unless it opts out, as the Notes panel does.
            guard window.styleMask.contains(.resizable),
                window.collectionBehavior.isDisjoint(with: [.fullScreenAuxiliary, .fullScreenNone])
            else { return nil }
            if window.styleMask.contains(.fullScreen) != wanted { window.toggleFullScreen(nil) }
            return .sent
        case .external(_, let window):
            if AXWindowAccess.isSettable(AXWindowAccess.fullScreenAttribute as String, on: window) {
                let result = AXUIElementSetAttributeValue(
                    window, AXWindowAccess.fullScreenAttribute,
                    wanted ? kCFBooleanTrue : kCFBooleanFalse)
                // No button after a failed write: a window that flipped anyway would flip back.
                return result == .success ? .sent : .unconfirmed
            }
            guard
                let button = AXWindowAccess.element(
                    window, AXWindowAccess.fullScreenButtonAttribute as String),
                AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
            else { return nil }
            return .sent
        }
    }
}
