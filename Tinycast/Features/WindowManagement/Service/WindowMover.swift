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

        var isFullScreen: Bool {
            switch self {
            case .external(_, let window): AXWindowAccess.isFullScreen(window)
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

    private var memory = WindowActionMemory<WindowKey>()
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
            MainActor.assumeIsolated { self?.memory.forget(key: key) }
        }
        windowCloseToken = NotificationToken(closeToken, center: .default)
    }

    /// The window a command targets, resolved once per press.
    private struct FocusedWindow {
        let surface: Surface
        let key: WindowKey
    }

    /// Turns the observed frame, the displays and the memory's verdict into a target.
    private typealias Resolver = (
        _ current: CGRect, _ screens: [WindowPlacementEngine.Screen],
        _ decision: WindowActionMemory<WindowKey>.Decision
    ) -> WindowPlacementEngine.Placement?

    /// Runs `command` against `target`'s focused window, returning whether anything changed.
    @discardableResult
    func perform(
        _ command: WindowCommand.ID, target: WindowTarget?, gap: CGFloat, cycle: WindowCycle
    ) -> Bool {
        guard let catalogued = WindowCommandCatalog.command(id: command),
            let focused = focusedWindow(of: target)
        else { return false }

        if catalogued.kind == .fullscreen {
            guard toggleFullScreen(focused.surface) else { return false }
            // The size chain is moot, but the pre-Tinycast frame is still the Restore target.
            memory.forgetCycle(key: focused.key)
            return true
        }
        return place(
            focused, command: command, gap: gap,
            cycleLength: {
                WindowPlacementEngine.cycleLength(for: command, screens: $0, cycle: cycle)
            }
        ) { current, screens, decision in
            WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: command, windowFrame: current, screens: screens, gap: gap,
                    step: decision.step, cycle: cycle, originScreenID: decision.originScreenID,
                    restoreFrame: decision.canRestore ? decision.restoreFrame : nil,
                    lastTileCommand: decision.lastTileCommand))
        }
    }

    /// Applies `size` to `target`'s focused window; Restore undoes it like any command.
    @discardableResult
    func perform(_ size: CustomWindowSize, target: WindowTarget?, gap: CGFloat) -> Bool {
        guard let focused = focusedWindow(of: target) else { return false }
        return place(
            focused, command: nil, gap: gap, cycleLength: { _ in 1 },
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
        cycleLength: ([WindowPlacementEngine.Screen]) -> Int, resolve: Resolver
    ) -> Bool {
        let surface = focused.surface
        let geometry = AXGeometry(screens: NSScreen.screens)
        // Tiling a natively fullscreen window fights the window server; leave it alone.
        guard !surface.isFullScreen, let current = surface.frame(in: geometry) else { return false }

        let screens = AXScreens.converted(NSScreen.screens, geometry: geometry)
        guard let host = WindowPlacementEngine.screen(containing: current, in: screens) else {
            return false
        }

        // One timestamp for the whole command, so the cycle timeout can't straddle two readings.
        let now = Date()
        let decision = memory.decide(
            key: focused.key, command: command, currentFrame: current, currentScreenID: host.id,
            cycleLength: cycleLength(screens), now: now)
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
                geometry: geometry)
        else { return false }

        let landedOn =
            WindowPlacementEngine.screen(containing: applied, in: screens)?.id
            ?? placement.screenID
        memory.commit(
            key: focused.key, command: command, decision: decision, appliedFrame: applied,
            screenID: landedOn, now: now)
        return !applied.equalTo(current)
    }

    // MARK: - Fullscreen

    /// `AXFullScreen`, then the green button. docs/features/window-management.md
    private func toggleFullScreen(_ surface: Surface) -> Bool {
        switch surface {
        case .own(let window):
            // AppKit fullscreens any resizable window unless it opts out, as the Notes panel does.
            guard window.styleMask.contains(.resizable),
                window.collectionBehavior.isDisjoint(with: [.fullScreenAuxiliary, .fullScreenNone])
            else { return false }
            window.toggleFullScreen(nil)
            return true
        case .external(_, let window):
            let target: CFBoolean =
                AXWindowAccess.isFullScreen(window) ? kCFBooleanFalse : kCFBooleanTrue
            if AXWindowAccess.isSettable(
                AXWindowAccess.fullScreenAttribute as String, on: window),
                AXUIElementSetAttributeValue(
                    window, AXWindowAccess.fullScreenAttribute, target) == .success
            {
                return true
            }
            guard
                let button = AXWindowAccess.element(
                    window, AXWindowAccess.fullScreenButtonAttribute as String)
            else { return false }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
    }
}
