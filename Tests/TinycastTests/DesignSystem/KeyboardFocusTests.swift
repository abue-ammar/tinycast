import AppKit
import Testing

@testable import Tinycast

/// The palette's keyboard belongs to the search field, and a preview's transport may never take it.
@MainActor
struct KeyboardFocusTests {
    @Test func theMarkedViewRefusesFocus() {
        #expect(MarkedView().refusesKeyboardFocus)
    }

    /// The real offender is `AVDesktopButton`, a private control the transport owns.
    @Test func aControlNestedUnderTheMarkRefusesFocus() {
        let marked = MarkedView()
        let bar = NSView()
        let button = NSButton()
        bar.addSubview(button)
        marked.addSubview(bar)
        #expect(button.refusesKeyboardFocus)
    }

    @Test func viewsOutsideTheMarkTakeFocus() {
        let root = NSView()
        let field = NSTextField()
        root.addSubview(field)
        root.addSubview(MarkedView())
        #expect(!field.refusesKeyboardFocus, "a sibling of the mark")
        #expect(!root.refusesKeyboardFocus, "an ancestor of the mark")
        #expect(!NSView().refusesKeyboardFocus, "an unparented view")
    }
}

/// Stands in for the player surface: what the mark means is "nothing under here takes focus".
private final class MarkedView: NSView, KeyboardFocusRefusing {}
