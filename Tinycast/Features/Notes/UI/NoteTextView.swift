import AppKit

@MainActor
protocol NoteTextViewActions: AnyObject {
    func noteTextViewCopy(_ textView: NoteTextView)
    func noteTextViewCut(_ textView: NoteTextView)
    func noteTextView(_ textView: NoteTextView, perform command: NoteMarkdownCommand)
    func noteTextViewFormattingState(_ textView: NoteTextView) -> Set<NoteMarkdownCommand>
    func noteTextView(_ textView: NoteTextView, openLinkAt displayLocation: Int) -> Bool
    func noteTextViewFocusChanged(_ textView: NoteTextView, isFocused: Bool)
    func noteTextViewWillBeginComposition(_ textView: NoteTextView)
    func noteTextViewDidEndComposition(_ textView: NoteTextView)
}

@MainActor
final class NoteTextView: NSTextView {
    weak var editorActions: NoteTextViewActions?
    var editorUndoManager: UndoManager?
    let taskOverlays = NoteTaskOverlayController()

    override var undoManager: UndoManager? { editorUndoManager }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { editorActions?.noteTextViewFocusChanged(self, isFocused: true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { editorActions?.noteTextViewFocusChanged(self, isFocused: false) }
        return resigned
    }

    override func copy(_ sender: Any?) {
        editorActions?.noteTextViewCopy(self)
    }

    override func cut(_ sender: Any?) {
        editorActions?.noteTextViewCut(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        let command: NoteMarkdownCommand? = switch (modifiers, key) {
        case (.command, "b"): .bold
        case (.command, "i"): .italic
        case (.command, "k"): .link
        case ([.command, .shift], "x"): .strikethrough
        case ([.command, .shift], "7"): .orderedList
        case ([.command, .shift], "8"): .unorderedList
        case ([.command, .shift], "9"): .taskList
        default: nil
        }
        guard let command else { return super.performKeyEquivalent(with: event) }
        editorActions?.noteTextView(self, perform: command)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let point = convert(event.locationInWindow, from: nil)
            let location = characterIndexForInsertion(at: point)
            if editorActions?.noteTextView(self, openLinkAt: location) == true { return }
        }
        super.mouseDown(with: event)
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        editorActions?.noteTextViewWillBeginComposition(self)
        super.setMarkedText(
            string,
            selectedRange: selectedRange,
            replacementRange: replacementRange)
    }

    override func unmarkText() {
        super.unmarkText()
        editorActions?.noteTextViewDidEndComposition(self)
    }
}
