import AppKit
// `@preconcurrency` downgrades AX diagnostics: `kAX…` are mutable C globals, but constant.
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

    /// A hung target must not stall main for the AX default. Per element, never inherited.
    private static let messagingTimeout: Float = 1
    /// Slack when checking whether the app honoured the size we asked for.
    private static let clampTolerance: CGFloat = 2

    private static let fullScreenAttribute = "AXFullScreen" as CFString
    private static let fullScreenButtonAttribute = "AXFullScreenButton" as CFString

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

        let application = AXUIElementCreateApplication(target.processIdentifier)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        guard let window = targetWindow(in: application) else { return false }
        AXUIElementSetMessagingTimeout(window, Self.messagingTimeout)

        let key = WindowKey(pid: target.processIdentifier, element: window)

        if catalogued.kind == .fullscreen {
            guard toggleFullScreen(window) else { return false }
            // The size chain is moot, but the pre-Tinycast frame is still the Restore target.
            memory.forgetCycle(key: key)
            return true
        }
        // Tiling a natively fullscreen window fights the window server; leave it alone.
        guard !isFullScreen(window), let current = frame(of: window) else { return false }

        let geometry = AXGeometry(screens: NSScreen.screens)
        let screens = Self.screens(NSScreen.screens, geometry: geometry)
        guard let host = WindowLayout.screen(containing: current, in: screens) else { return false }

        // One timestamp for the whole command, so the cycle timeout can't straddle two readings.
        let now = Date()
        let decision = memory.decide(
            key: key, command: command, currentFrame: current, currentScreenID: host.id,
            cycleEnabled: cycleOnRepeat, now: now)

        let input = WindowLayout.Input(
            command: command, windowFrame: current, screens: screens, gap: gap, step: decision.step,
            restoreFrame: decision.canRestore ? decision.restoreFrame : nil,
            lastTileCommand: decision.lastTileCommand)
        guard let placement = WindowLayout.placement(for: input) else { return false }

        // Checked before any write, so an unpositionable window is left untouched.
        guard isSettable(kAXPositionAttribute, on: window) else { return false }
        let canResize =
            placement.resizes && isSettable(kAXSizeAttribute, on: window)

        guard
            let applied = apply(
                placement, to: window, application: application, current: current,
                canResize: canResize, screens: screens, gap: gap)
        else { return false }

        let landedOn =
            WindowLayout.screen(containing: applied, in: screens)?.id ?? placement.screenID
        memory.commit(
            key: key, command: command, decision: decision, appliedFrame: applied,
            screenID: landedOn, now: now)
        return !applied.equalTo(current)
    }

    // MARK: - Applying a placement

    private func apply(
        _ placement: WindowLayout.Placement, to window: AXUIElement, application: AXUIElement,
        current: CGRect, canResize: Bool, screens: [WindowLayout.Screen], gap: CGFloat
    ) -> CGRect? {
        let destination = screens.first { $0.id == placement.screenID }
        let canvas = destination.map {
            WindowLayout.canvas(
                $0.visibleFrame, gap: WindowLayout.sanitizedGap(gap, in: $0.visibleFrame))
        }

        guard canResize else {
            // It refuses to resize, so place the size it has inside the slot and stop.
            var slot = placement.anchor.place(current.size, in: placement.frame)
            if let canvas { slot = WindowLayout.clamped(slot, into: canvas) }
            guard setPosition(WindowLayout.rounded(slot).origin, on: window) else { return nil }
            return frame(of: window) ?? current
        }

        let restoreEnhancedUI = suppressEnhancedUserInterface(on: application)
        defer { restoreEnhancedUI() }

        // size → position → size. See docs/features/window-management.md#applying-a-placement.
        _ = setSize(placement.frame.size, on: window)
        guard setPosition(placement.frame.origin, on: window) else {
            _ = setSize(current.size, on: window)  // Roll the shrink back; nothing visibly moved.
            return nil
        }
        _ = setSize(placement.frame.size, on: window)

        guard var actual = frame(of: window) else { return placement.frame }

        // The second resize can shift the origin: some apps anchor on a different corner.
        if abs(actual.minX - placement.frame.minX) > Self.clampTolerance
            || abs(actual.minY - placement.frame.minY) > Self.clampTolerance
        {
            _ = setPosition(placement.frame.origin, on: window)
            actual = frame(of: window) ?? actual
        }

        // An app-imposed minimum: re-place once per the anchor. No loop, which would jitter.
        if actual.width > placement.frame.width + Self.clampTolerance
            || actual.height > placement.frame.height + Self.clampTolerance
        {
            var slot = placement.anchor.place(actual.size, in: placement.frame)
            if let canvas { slot = WindowLayout.clamped(slot, into: canvas) }
            _ = setPosition(WindowLayout.rounded(slot).origin, on: window)
            actual = frame(of: window) ?? actual
        }
        return actual
    }

    // MARK: - Finding the window

    private func targetWindow(in application: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = element(application, attribute), isEligible(window) { return window }
        }
        // Last resort for apps that report neither: the first window that isn't a sheet or a panel.
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                == .success,
            let windows = value as? [AXUIElement]
        else { return nil }
        return windows.first(where: isEligible)
    }

    /// A real, restorable window: not a sheet, popover or minimized one, and it reports geometry.
    private func isEligible(_ window: AXUIElement) -> Bool {
        guard string(window, kAXRoleAttribute) == (kAXWindowRole as String) else { return false }
        if bool(window, kAXMinimizedAttribute) == true { return false }
        return frame(of: window) != nil
    }

    // MARK: - Fullscreen

    private func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, Self.fullScreenAttribute, &value) == .success
        else { return false }
        return (value as? Bool) ?? false
    }

    /// `AXFullScreen`, then the green button. docs/features/window-management.md
    private func toggleFullScreen(_ window: AXUIElement) -> Bool {
        let target: CFBoolean = isFullScreen(window) ? kCFBooleanFalse : kCFBooleanTrue
        if isSettable(Self.fullScreenAttribute as String, on: window),
            AXUIElementSetAttributeValue(window, Self.fullScreenAttribute, target) == .success
        {
            return true
        }
        guard let button = element(window, Self.fullScreenButtonAttribute as String) else {
            return false
        }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// Cleared for the writes, never while VoiceOver runs. See docs/features/window-management.md.
    private func suppressEnhancedUserInterface(on application: AXUIElement) -> () -> Void {
        let attribute = "AXEnhancedUserInterface" as CFString
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return {} }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute, &value) == .success,
            (value as? Bool) == true
        else { return {} }
        AXUIElementSetAttributeValue(application, attribute, kCFBooleanFalse)
        return { AXUIElementSetAttributeValue(application, attribute, kCFBooleanTrue) }
    }

    // MARK: - Screens

    /// Cocoa screens converted into the AX space `WindowLayout` works in.
    private static func screens(
        _ screens: [NSScreen], geometry: AXGeometry
    )
        -> [WindowLayout.Screen]
    {
        screens.enumerated().map { index, screen in
            let number =
                screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber
            // A display with no number still needs a stable, collision-free id for this call.
            return WindowLayout.Screen(
                id: number.map { Int($0.uint32Value) } ?? -(index + 1),
                frame: geometry.flip(screen.frame),
                visibleFrame: geometry.flip(screen.visibleFrame))
        }
    }

    // MARK: - Accessibility primitives

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute),
            let size = size(window, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func setPosition(_ origin: CGPoint, on window: AXUIElement) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            == .success
    }

    private func setSize(_ size: CGSize, on window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    private func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute, type: .cgPoint) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute, type: .cgSize) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private func axValue(_ element: AXUIElement, _ attribute: String, type: AXValueType) -> AXValue? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // Type checked by CFGetTypeID above; `as?` on a CF type is a compile error.

        let axValue = value as! AXValue
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    private func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Type checked by CFGetTypeID above; `as?` on a CF type is a compile error.

        return (value as! AXUIElement)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    private func isSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }
}

/// The one Cocoa↔AX converter. See docs/features/window-management.md#coordinate-space.
struct AXGeometry {
    let anchorHeight: CGFloat

    /// Snapshot once per command: `NSScreen.screens` can change, and mixing anchors corrupts.
    @MainActor
    init(screens: [NSScreen]) {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        anchorHeight = primary?.frame.height ?? 0
    }

    /// An involution through `maxY`, never scaled. docs/features/window-management.md
    func flip(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x, y: anchorHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
