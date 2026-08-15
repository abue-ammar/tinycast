import AppKit

@MainActor
final class NoteTextView: NSTextView {
    var editorUndoManager: UndoManager?

    override var undoManager: UndoManager? { editorUndoManager }
}
