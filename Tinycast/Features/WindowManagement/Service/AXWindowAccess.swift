import AppKit
// `@preconcurrency` downgrades AX diagnostics: `kAX…` are mutable C globals, but constant.
@preconcurrency import ApplicationServices

/// Every `AXUIElement` call in the feature. Shared, so the mover and the layout runner cannot
/// disagree about what a window is or how one is written.
@MainActor
enum AXWindowAccess {
    /// A hung target must not stall main for the AX default. Per element, never inherited.
    static let messagingTimeout: Float = 1
    /// Slack when checking whether the app honoured the size we asked for.
    static let clampTolerance: CGFloat = 2

    static let fullScreenAttribute = "AXFullScreen" as CFString
    static let fullScreenButtonAttribute = "AXFullScreenButton" as CFString

    // MARK: - Finding windows

    static func application(for pid: pid_t, timeout: Float = messagingTimeout) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        return application
    }

    /// The window a command acts on: focused, else main, else the first eligible one.
    static func targetWindow(in application: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = element(application, attribute), isEligible(window) { return window }
        }
        return windows(in: application).first(where: isEligible)
    }

    /// Every window the app reports, unfiltered and in its own order.
    static func windows(in application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                == .success,
            let windows = value as? [AXUIElement]
        else { return [] }
        return windows
    }

    /// A real, restorable window: not a sheet, popover or minimized one, and it reports geometry.
    static func isEligible(_ window: AXUIElement) -> Bool {
        guard string(window, kAXRoleAttribute) == (kAXWindowRole as String) else { return false }
        if bool(window, kAXMinimizedAttribute) == true { return false }
        return frame(of: window) != nil
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, fullScreenAttribute, &value) == .success
        else { return false }
        return (value as? Bool) ?? false
    }

    // MARK: - Writing a frame

    /// The one write sequence, so a stubborn app lands the same way from any caller.
    /// See docs/features/window-management.md#applying-a-placement.
    static func write(
        _ target: CGRect, anchor: WindowPlacementEngine.Anchor, to window: AXUIElement,
        current: CGRect, canResize: Bool, canvas: CGRect?
    ) -> CGRect? {
        guard canResize else {
            // It refuses to resize, so place the size it has inside the slot and stop.
            var slot = anchor.place(current.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            guard setPosition(WindowPlacementEngine.rounded(slot).origin, on: window) else {
                return nil
            }
            return frame(of: window) ?? current
        }

        // size → position → size. See docs/features/window-management.md#applying-a-placement.
        _ = setSize(target.size, on: window)
        guard setPosition(target.origin, on: window) else {
            _ = setSize(current.size, on: window)  // Roll the shrink back; nothing visibly moved.
            return nil
        }
        _ = setSize(target.size, on: window)

        guard var actual = frame(of: window) else { return target }

        // The second resize can shift the origin: some apps anchor on a different corner.
        if abs(actual.minX - target.minX) > clampTolerance
            || abs(actual.minY - target.minY) > clampTolerance
        {
            _ = setPosition(target.origin, on: window)
            actual = frame(of: window) ?? actual
        }

        // An app-imposed minimum: re-place once per the anchor. No loop, which would jitter.
        if actual.width > target.width + clampTolerance
            || actual.height > target.height + clampTolerance
        {
            var slot = anchor.place(actual.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            _ = setPosition(WindowPlacementEngine.rounded(slot).origin, on: window)
            actual = frame(of: window) ?? actual
        }
        return actual
    }

    /// Cleared for the writes, never while VoiceOver runs. See docs/features/window-management.md.
    static func suppressEnhancedUserInterface(on application: AXUIElement) -> () -> Void {
        let attribute = "AXEnhancedUserInterface" as CFString
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return {} }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute, &value) == .success,
            (value as? Bool) == true
        else { return {} }
        AXUIElementSetAttributeValue(application, attribute, kCFBooleanFalse)
        return { AXUIElementSetAttributeValue(application, attribute, kCFBooleanTrue) }
    }

    // MARK: - Primitives

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute),
            let size = size(window, kAXSizeAttribute)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func setPosition(_ origin: CGPoint, on window: AXUIElement) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            == .success
    }

    static func setSize(_ size: CGSize, on window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute, type: .cgPoint) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute, type: .cgSize) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    static func axValue(
        _ element: AXUIElement, _ attribute: String, type: AXValueType
    ) -> AXValue? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        // Type checked by CFGetTypeID above; `as?` on a CF type is a compile error.

        let axValue = value as! AXValue
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Type checked by CFGetTypeID above; `as?` on a CF type is a compile error.

        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    static func isSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }
}
