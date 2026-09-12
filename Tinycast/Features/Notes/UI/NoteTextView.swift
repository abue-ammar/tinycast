import AppKit

@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?

    override var undoManager: UndoManager? { editorUndoManager }
}
