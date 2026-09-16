import AppKit
@preconcurrency import ApplicationServices

/// Applies window commands over AX. See docs/features/window-management.md#applying-a-placement.
@MainActor
final class WindowMover {
    /// `CFEqual`/`CFHash` are the supported identity; the pid separates two processes' elements.
    private struct WindowKey: Hashable {
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

    private var memory = WindowActionMemory<WindowKey>()
    private var terminationToken: NotificationToken?

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
                self?.memory.forget { $0.pid == pid }
            }
        }
        terminationToken = NotificationToken(token, center: NSWorkspace.shared.notificationCenter)
    }

    /// The focused window of the app a command targets, resolved once per press.
    private struct FocusedWindow {
        let application: AXUIElement
        let window: AXUIElement
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
        _ command: WindowCommand.ID, target: NSRunningApplication?, gap: CGFloat,
        cycle: WindowCycle
    ) -> Bool {
        guard let catalogued = WindowCommandCatalog.command(id: command),
            let focused = focusedWindow(of: target)
        else { return false }

        if catalogued.kind == .fullscreen {
            guard toggleFullScreen(focused.window) else { return false }
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
    func perform(_ size: CustomWindowSize, target: NSRunningApplication?, gap: CGFloat) -> Bool {
        guard let focused = focusedWindow(of: target) else { return false }
        return place(
            focused, command: nil, gap: gap, cycleLength: { _ in 1 },
            resolve: { current, screens, _ in
                size.placement(for: current, screens: screens, gap: gap)
            })
    }

    private func focusedWindow(of target: NSRunningApplication?) -> FocusedWindow? {
        // Invoked from an explicit user gesture, so prompting for the grant is appropriate here.
        guard Permissions.ensureAccessibility() else { return nil }
        guard let target, !target.isTerminated,
            target.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }

        let application = AXWindowAccess.application(for: target.processIdentifier)
        guard let window = AXWindowAccess.targetWindow(in: application) else { return nil }
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        return FocusedWindow(
            application: application, window: window,
            key: WindowKey(pid: target.processIdentifier, element: window))
    }

    /// The one decide → resolve → write → commit sequence every geometry press runs through.
    private func place(
        _ focused: FocusedWindow, command: WindowCommand.ID?, gap: CGFloat,
        cycleLength: ([WindowPlacementEngine.Screen]) -> Int, resolve: Resolver
    ) -> Bool {
        let window = focused.window
        // Tiling a natively fullscreen window fights the window server; leave it alone.
        guard !AXWindowAccess.isFullScreen(window),
            let current = AXWindowAccess.frame(of: window)
        else { return false }

        let geometry = AXGeometry(screens: NSScreen.screens)
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
        guard AXWindowAccess.isSettable(kAXPositionAttribute, on: window) else { return false }
        let canResize =
            placement.resizes && AXWindowAccess.isSettable(kAXSizeAttribute, on: window)

        let destination = screens.first { $0.id == placement.screenID }
        let canvas = destination.map {
            WindowPlacementEngine.canvas(
                $0.visibleFrame,
                gap: WindowPlacementEngine.sanitizedGap(gap, in: $0.visibleFrame))
        }
        let restoreEnhancedUI =
            canResize
            ? AXWindowAccess.suppressEnhancedUserInterface(on: focused.application) : {}
        defer { restoreEnhancedUI() }

        guard
            let applied = AXWindowAccess.write(
                placement.frame, anchor: placement.anchor, to: window, current: current,
                canResize: canResize, canvas: canvas)
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
    private func toggleFullScreen(_ window: AXUIElement) -> Bool {
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
