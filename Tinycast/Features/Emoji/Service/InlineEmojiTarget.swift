import AppKit
@preconcurrency import ApplicationServices

@MainActor
struct InlineEmojiTarget {
    let app: NSRunningApplication
    let element: AXUIElement
    let start: Int
    let anchor: CGRect
    let needsEnhancedUserInterface: Bool

    private static let enhancedUserInterface = "AXEnhancedUserInterface" as CFString

    static func capture(query: String) -> Self? {
        guard NSApp.keyWindow == nil,
            let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier != Bundle.main.bundleIdentifier,
            let element = AccessibilityText.focusedElement(in: app),
            !isSecure(element),
            let range = selectedRange(in: element), range.length == 0
        else { return nil }
        let keyword = ":" + query
        let start = range.location - keyword.utf16.count
        guard start >= 0,
            text(in: element, range: NSRange(location: start, length: keyword.utf16.count)) == keyword,
            isBoundary(start, in: element)
        else { return nil }
        let caret = bounds(in: element, range: range)
        // Chromium reports no caret until a screen reader appears; the field still places the list.
        guard let anchor = caret ?? frame(of: element) else { return nil }
        return Self(
            app: app, element: element, start: start, anchor: anchor,
            needsEnhancedUserInterface: caret == nil && isWebField(element))
    }

    /// Chromium serves caret geometry only to a screen reader, about two seconds after one appears.
    static func enableEnhancedUserInterface(in pid: pid_t) -> Bool {
        let application = AccessibilityText.application(pid)
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(application, enhancedUserInterface, &value)
        guard value as? Bool != true else { return false }
        AXUIElementSetAttributeValue(application, enhancedUserInterface, kCFBooleanTrue)
        return true
    }

    static func restoreEnhancedUserInterface(in pid: pid_t) {
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return }
        AXUIElementSetAttributeValue(
            AccessibilityText.application(pid), enhancedUserInterface, kCFBooleanFalse)
    }

    func isFocused() -> Bool {
        guard NSApp.keyWindow == nil, !app.isTerminated,
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
            let focused = AccessibilityText.focusedElement(in: app)
        else { return false }
        return CFEqual(element, focused) && !Self.isSecure(focused)
    }

    func matches(query: String) -> Bool {
        let keyword = ":" + query
        guard isFocused(), let range = Self.selectedRange(in: element),
            range.length == 0, range.location == start + keyword.utf16.count
        else { return false }
        return Self.text(
            in: element, range: NSRange(location: start, length: keyword.utf16.count)) == keyword
    }

    private static func isBoundary(_ start: Int, in element: AXUIElement) -> Bool {
        guard start > 0 else { return true }
        guard let previous = text(in: element, range: NSRange(location: start - 1, length: 1)),
            let character = previous.last
        else { return false }
        return InlineEmojiPolicy.canStart(after: character)
    }

    /// Native fields never speak text markers, and gain nothing from the screen-reader flag.
    private static func isWebField(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            element, kAXSelectedTextMarkerRangeAttribute as CFString, &value) == .success
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
        return value as? String == kAXSecureTextFieldSubrole
    }

    private static func selectedRange(in element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let range = unpack(value, .cfRange, CFRange()), range.location >= 0, range.length >= 0
        else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func text(in element: AXUIElement, range: NSRange) -> String? {
        var value: CFTypeRef?
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        if AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
            let text = value as? String
        {
            return text
        }
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
            let text = value as? String, let stringRange = Range(range, in: text)
        else { return nil }
        return String(text[stringRange])
    }

    private static func bounds(in element: AXUIElement, range: NSRange) -> CGRect? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value) == .success,
            let bounds = unpack(value, .cgRect, CGRect.zero), isUsable(bounds)
        else { return nil }
        return bounds
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
            let origin = unpack(position, .cgPoint, CGPoint.zero),
            let extent = unpack(size, .cgSize, CGSize.zero)
        else { return nil }
        let frame = CGRect(origin: origin, size: extent)
        return isUsable(frame) ? frame : nil
    }

    private static func unpack<Value>(_ value: CFTypeRef?, _ type: AXValueType, _ initial: Value) -> Value? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = initial
        return AXValueGetValue(value as! AXValue, type, &result) ? result : nil
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isInfinite && !rect.isNull && rect.height > 0 && rect.minX.isFinite && rect.minY.isFinite
    }
}
