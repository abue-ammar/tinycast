import AppKit
@preconcurrency import ApplicationServices

@MainActor
struct InlineEmojiTarget {
    let app: NSRunningApplication
    let element: AXUIElement
    let start: Int
    let caret: CGRect

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
            isBoundary(start, in: element),
            let caret = bounds(in: element, range: range)
        else { return nil }
        return Self(app: app, element: element, start: start, caret: caret)
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
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0,
            range.length >= 0
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
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var bounds = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &bounds), !bounds.isInfinite,
            !bounds.isNull, bounds.height > 0, bounds.minX.isFinite, bounds.minY.isFinite
        else { return nil }
        return bounds
    }
}
