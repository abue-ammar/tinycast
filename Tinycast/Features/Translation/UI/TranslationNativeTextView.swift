import AppKit
import SwiftUI

/// The text view behind both columns; its statics are the focus ring the screen and panel walk.
@MainActor
final class TranslationNativeTextView: NSTextView {
    var role = TranslationTextView.Role.source {
        didSet { setAccessibilityLabel(role == .source ? "Source text" : "Translation") }
    }
    weak var host: TranslationTextView.Coordinator?

    /// Its own, so an undo can never reach back into the palette's search field.
    private let ownUndoManager = UndoManager()
    private static weak var source: TranslationNativeTextView?
    private static weak var result: TranslationNativeTextView?

    override var undoManager: UndoManager? { ownUndoManager }

    /// The read-only translation takes ⇥ too, even while empty, so the ring never collapses.
    override var acceptsFirstResponder: Bool { true }

    /// The text an input method has committed; marked text is a draft of a draft.
    var committedText: String {
        let marked = markedRange()
        guard hasMarkedText(), marked.location != NSNotFound, marked.length > 0 else { return string }
        return (string as NSString).replacingCharacters(in: marked, with: "")
    }

    static func register(_ view: TranslationNativeTextView) {
        switch view.role {
        case .source: source = view
        case .result: result = view
        }
    }

    static func unregister(_ view: TranslationNativeTextView) {
        if source === view { source = nil }
        if result === view { result = nil }
    }

    static func cycleFocus(backwards: Bool) {
        let ring = [source, result].compactMap { $0 }
        guard let window = ring.first?.window else { return }
        let step = backwards ? -1 : 1
        let next: Int
        if let current = ring.firstIndex(where: { window.firstResponder === $0 }) {
            next = (current + step + ring.count) % ring.count
        } else {
            next = backwards ? ring.count - 1 : 0
        }
        window.makeFirstResponder(ring[next])
    }

    static func focusSource(in window: NSWindow?) {
        guard let source, let host = source.window, window == nil || host === window,
            host.firstResponder !== source
        else { return }
        host.makeFirstResponder(source)
    }

    // MARK: - Keys

    /// ⌘↵ and ⌘K, only from the column holding the keyboard and never over marked text.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, !hasMarkedText(),
            event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
        else { return super.performKeyEquivalent(with: event) }
        if event.specialKey == .carriageReturn || event.specialKey == .enter {
            if !event.isARepeat { host?.copyTranslation() }
            return true
        }
        if ASCIIKeyboardLayout.character(for: event) == "k" {
            if !event.isARepeat { host?.openMenu() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// A bare Escape belongs to the palette's own policy; NSTextView would open word completion.
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "\u{1B}", !hasMarkedText(),
            event.modifierFlags.isDisjoint(with: [.command, .shift, .option, .control])
        {
            nextResponder?.keyDown(with: event)
            return
        }
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        Self.cycleFocus(backwards: false)
    }

    override func insertBacktab(_ sender: Any?) {
        Self.cycleFocus(backwards: true)
    }

    // MARK: - Focus and appearance

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        host?.focusChanged(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        host?.focusChanged(false)
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    func applyColors() {
        textColor = NSColor(Theme.Colors.textPrimary)
        insertionPointColor = NSColor(Theme.Colors.textPrimary)
        selectedTextAttributes = [
            .backgroundColor: NSColor(Theme.Colors.selection),
            .foregroundColor: NSColor(Theme.Colors.textPrimary)
        ]
    }
}
