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

    /// Runs `command` against `target`'s focused window, returning whether anything changed.
    @discardableResult
    func perform(
        _ command: WindowCommand.ID, target: NSRunningApplication?, gap: CGFloat,
        cycleOnRepeat: Bool
    ) -> Bool {
        // Invoked from an explicit user gesture, so prompting for the grant is appropriate here.
        guard Permissions.ensureAccessibility() else { return false }
        guard let target, !target.isTerminated,
            target.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return false }
        guard let catalogued = WindowCommandCatalog.command(id: command) else { return false }

        let application = AXWindowAccess.application(for: target.processIdentifier)
        guard let window = AXWindowAccess.targetWindow(in: application) else { return false }
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)

        let key = WindowKey(pid: target.processIdentifier, element: window)

        if catalogued.kind == .fullscreen {
            guard toggleFullScreen(window) else { return false }
            // The size chain is moot, but the pre-Tinycast frame is still the Restore target.
            memory.forgetCycle(key: key)
            return true
        }
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
            key: key, command: command, currentFrame: current, currentScreenID: host.id,
            cycleEnabled: cycleOnRepeat, now: now)

        let input = WindowPlacementEngine.Input(
            command: command, windowFrame: current, screens: screens, gap: gap, step: decision.step,
            restoreFrame: decision.canRestore ? decision.restoreFrame : nil,
            lastTileCommand: decision.lastTileCommand)
        guard let placement = WindowPlacementEngine.placement(for: input) else { return false }

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
            ? AXWindowAccess.suppressEnhancedUserInterface(on: application) : {}
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
            key: key, command: command, decision: decision, appliedFrame: applied,
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
