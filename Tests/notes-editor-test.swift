import AppKit
import Foundation

@main
@MainActor
struct NotesEditorTests {
    private static var failures = 0

    static func main() {
        _ = NSApplication.shared
        testProjectedEditingAndUndoIsolation()
        print(failures == 0 ? "Notes editor tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testProjectedEditingAndUndoIsolation() {
        let firstID = NoteID(rawValue: "First.md")
        var changes: [String] = []
        let view = NoteEditorView(
            input: NoteEditorInput(
                id: firstID,
                source: "**bold** [link](https://example.com)",
                epoch: 1),
            onSourceChange: { changes.append($0) },
            onContentHeightChange: { _ in },
            onReady: { _ in },
            onOpenLink: { _ in })
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = NoteTextView(usingTextLayoutManager: true)
        textView.editorActions = coordinator
        textView.editorUndoManager = coordinator.editorUndoManager
        coordinator.textView = textView
        coordinator.install(view.input, resetUndo: false)

        check("inactive source markers collapse from layout", textView.string == "bold link")
        let sourceWidth = (view.input.source as NSString).size(withAttributes: nil).width
        let displayWidth = (textView.string as NSString).size(withAttributes: nil).width
        check("projection is narrower than literal source", displayWidth < sourceWidth)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.contentView = textView
        window.makeFirstResponder(textView)
        check("focused caret reveals its complete source construct", textView.string.hasPrefix("**bold**"))
        window.makeFirstResponder(nil)
        check("leaving the editor collapses source markers again", textView.string == "bold link")

        let accepted = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 4, length: 0),
            replacementString: "!")
        check("mapped typing replaces canonical source itself", !accepted)
        check("one edit emits one source delivery", changes.count == 1)
        check("typing preserves hidden Markdown", changes.last == "**bold**! [link](https://example.com)")
        check("mapped edits register native undo", coordinator.editorUndoManager.canUndo)

        coordinator.editorUndoManager.undo()
        check("undo emits exactly one inverse source delivery", changes.count == 2)
        check("undo restores exact Markdown", changes.last == view.input.source)
        coordinator.editorUndoManager.redo()
        check("redo emits exactly one source delivery", changes.count == 3)
        check("redo restores the mapped edit", changes.last == "**bold**! [link](https://example.com)")
        coordinator.editorUndoManager.undo()
        check("a second undo restores the starting source", changes.last == view.input.source)

        _ = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 0, length: 0),
            replacementString: "prefix ")
        check("a second edit restores undo availability", coordinator.editorUndoManager.canUndo)
        let second = NoteEditorInput(
            id: NoteID(rawValue: "Second.md"),
            source: "short",
            epoch: 2)
        coordinator.install(second, resetUndo: true)
        check("switching notes clears stale undo ranges", !coordinator.editorUndoManager.canUndo)
        coordinator.editorUndoManager.undo()
        check("undo after a switch leaves the new note intact", textView.string == "short")

        _ = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: 5, length: 0),
            replacementString: " edit")
        let reloaded = NoteEditorInput(id: second.id, source: "external", epoch: 3)
        coordinator.install(reloaded, resetUndo: true)
        coordinator.editorUndoManager.undo()
        check("undo after an external reload leaves reloaded source intact", textView.string == "external")

        let beforeComposition = changes.count
        coordinator.noteTextViewWillBeginComposition(textView)
        textView.textStorage?.replaceCharacters(
            in: NSRange(location: (textView.string as NSString).length, length: 0),
            with: "語")
        coordinator.noteTextViewDidEndComposition(textView)
        check("marked text commits as one source delivery", changes.count == beforeComposition + 1)
        check("marked text preserves exact Unicode source", changes.last == "external語")

        let beforeCancellation = changes.count
        coordinator.noteTextViewWillBeginComposition(textView)
        coordinator.noteTextViewDidEndComposition(textView)
        check("cancelled marked text emits no source change", changes.count == beforeCancellation)
    }

    private static func check(_ message: String, _ condition: @autoclosure () -> Bool) {
        guard condition() else {
            failures += 1
            print("FAIL: \(message)")
            return
        }
    }
}
