import AppKit
import Foundation

@main
@MainActor
struct NotesEditorTests {
    private static var failures = 0

    static func main() async {
        _ = NSApplication.shared
        testLiteralEditingAndNativeCommands()
        testUndoIsolation()
        testDocumentScopedHeightReports()
        testContentHeight()
        await testUsageBoundsObservation()
        await testLiveHeightShrinksAfterDeletion()
        print(failures == 0 ? "Notes editor tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testLiteralEditingAndNativeCommands() {
        let source = "# Heading\n\nThis is **bold** and [linked](https://example.com)."
        let input = NoteEditorInput(
            id: NoteID(rawValue: "Literal.md"),
            source: source,
            epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: input, onSourceChange: { changes.append($0) })

        check("the editor displays literal Markdown source", editor.textView.string == source)
        check("the plain editor enables native Find", editor.textView.usesFindPanel)

        let boldRange = (editor.textView.string as NSString).range(of: "**bold**")
        editor.textView.setSelectedRange(boldRange)
        editor.textView.copy(nil)
        check(
            "native Copy preserves literal Markdown",
            NSPasteboard.general.string(forType: .string) == "**bold**")

        editor.textView.cut(nil)
        check("native Cut publishes one literal source update", changes.count == 1)
        check("native Cut removes the selected source", !editor.textView.string.contains("**bold**"))
        editor.coordinator.editorUndoManager.undo()
        check("native Undo restores the literal source", editor.textView.string == source)
        editor.coordinator.editorUndoManager.redo()
        check("native Redo restores the cut", editor.textView.string == changes.last)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(" [literal](url)", forType: .string)
        let end = (editor.textView.string as NSString).length
        editor.textView.setSelectedRange(NSRange(location: end, length: 0))
        editor.textView.paste(nil)
        check("native Paste inserts exact source", editor.textView.string.hasSuffix(" [literal](url)"))

        let unicode = " 🧑🏽‍💻e\u{301}"
        editor.textView.insertText(unicode, replacementRange: editor.textView.selectedRange())
        check("emoji and combining marks remain exact", editor.textView.string.hasSuffix(unicode))

        let markedLocation = (editor.textView.string as NSString).length
        editor.textView.setSelectedRange(NSRange(location: markedLocation, length: 0))
        editor.textView.setMarkedText(
            "語",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.textView.unmarkText()
        check("marked text commits through native AppKit editing", editor.textView.string.hasSuffix("語"))
        check("every published value equals the displayed source", changes.last == editor.textView.string)
    }

    private static func testUndoIsolation() {
        let first = NoteEditorInput(
            id: NoteID(rawValue: "First.md"),
            source: "First",
            epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: first, onSourceChange: { changes.append($0) })
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.textView.insertText(" edit", replacementRange: editor.textView.selectedRange())
        check("native editing registers Undo", editor.coordinator.editorUndoManager.canUndo)

        let second = NoteEditorInput(
            id: NoteID(rawValue: "Second.md"),
            source: "Second",
            epoch: 2)
        editor.coordinator.parent = view(for: second, onSourceChange: { changes.append($0) })
        editor.coordinator.update(second)
        check("switching notes installs the replacement source", editor.textView.string == "Second")
        check("switching notes clears stale Undo", !editor.coordinator.editorUndoManager.canUndo)
        editor.coordinator.editorUndoManager.undo()
        check("Undo after a switch leaves the new note intact", editor.textView.string == "Second")

        editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        editor.textView.insertText(" draft", replacementRange: editor.textView.selectedRange())
        let external = NoteEditorInput(id: second.id, source: "External", epoch: 3)
        editor.coordinator.parent = view(for: external, onSourceChange: { changes.append($0) })
        editor.coordinator.update(external)
        check("a clean external reload replaces the displayed source", editor.textView.string == "External")
        check("a clean external reload clears stale Undo", !editor.coordinator.editorUndoManager.canUndo)
    }

    private static func testDocumentScopedHeightReports() {
        let first = NoteEditorInput(
            id: NoteID(rawValue: "First.md"),
            source: "First",
            epoch: 1)
        var reports: [(NoteEditorInput, CGFloat)] = []
        let editor = makeEditor(
            input: first,
            onHeightChange: { reports.append(($0, $1)) })
        reports.removeAll()

        let second = NoteEditorInput(
            id: NoteID(rawValue: "Second.md"),
            source: (0..<40).map { "Line \($0)" }.joined(separator: "\n"),
            epoch: 2)
        editor.coordinator.parent = view(
            for: second,
            onHeightChange: { reports.append(($0, $1)) })
        editor.coordinator.update(second)
        editor.coordinator.reportHeight()

        check("stale height reports cannot identify the replacement note", reports.allSatisfy {
            $0.0.id == second.id && $0.0.epoch == second.epoch
        })
        check("the replacement note reports a laid-out height", reports.last?.1 ?? 0 > 0)
    }

    private static func testContentHeight() {
        let short = NoteEditorView.contentHeight(for: "Short", width: 320)
        let long = NoteEditorView.contentHeight(
            for: (0..<80).map { "Line \($0) with enough literal text to wrap" }
                .joined(separator: "\n"),
            width: 320)
        check("literal editor height grows with laid-out content", long > short)
        check(
            "Markdown markers receive no rendered height treatment",
            NoteEditorView.contentHeight(for: "**plain**", width: 320)
                == NoteEditorView.contentHeight(for: "123456789", width: 320))
    }

    private static func testUsageBoundsObservation() async {
        let input = NoteEditorInput(
            id: NoteID(rawValue: "Observed.md"),
            source: "Short",
            epoch: 1)
        var heights: [CGFloat] = []
        let editor = makeEditor(
            input: input,
            onHeightChange: { _, height in heights.append(height) })
        await Task.yield()
        let shortHeight = heights.last ?? 0
        heights.removeAll()
        editor.textView.delegate = nil

        editor.textView.string = (0..<80).map { "Observed line \($0)" }.joined(separator: "\n")
        ensureEditorLayout(editor.textView)
        await waitUntil { heights.contains { $0 > shortHeight } }
        let expandedHeight = heights.last(where: { $0 > shortHeight }) ?? shortHeight
        heights.removeAll()

        editor.textView.string = "Short"
        ensureEditorLayout(editor.textView)
        await waitUntil { heights.contains { $0 < expandedHeight } }

        check(
            "settled TextKit usage bounds report deletion shrink independently of edit timing",
            heights.contains { $0 < expandedHeight })
    }

    private static func testLiveHeightShrinksAfterDeletion() async {
        let input = NoteEditorInput(
            id: NoteID(rawValue: "Resize.md"),
            source: "Short",
            epoch: 1)
        var heights: [CGFloat] = []
        let editor = makeEditor(
            input: input,
            onHeightChange: { _, height in heights.append(height) })
        heights.removeAll()

        editor.textView.selectAll(nil)
        editor.textView.insertText(
            (0..<80).map { "Expanded line \($0)" }.joined(separator: "\n"),
            replacementRange: editor.textView.selectedRange())
        let expandedHeight = heights.last ?? 0
        let reportsBeforeDeletion = heights.count
        let retainedPrefix = (editor.textView.string as NSString).range(of: "Expanded line 4\n")
        let deletionStart = NSMaxRange(retainedPrefix)
        editor.textView.setSelectedRange(
            NSRange(
                location: deletionStart,
                length: (editor.textView.string as NSString).length - deletionStart))
        editor.textView.deleteBackward(nil)

        await waitUntil {
            heights.dropFirst(reportsBeforeDeletion).contains { $0 < expandedHeight }
        }

        check("live editing expands the measured editor height", expandedHeight > 0)
        check(
            "deleting rows reports a smaller settled height without another edit",
            heights.dropFirst(reportsBeforeDeletion).contains { $0 < expandedHeight })
    }

    private static func ensureEditorLayout(_ textView: NSTextView) {
        guard let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        layoutManager.ensureLayout(for: contentManager.documentRange)
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<20 {
            if condition() { return }
            await Task.yield()
        }
    }

    private static func makeEditor(
        input: NoteEditorInput,
        onSourceChange: @escaping (String) -> Void = { _ in },
        onHeightChange: @escaping (NoteEditorInput, CGFloat) -> Void = { _, _ in }
    ) -> (coordinator: NoteEditorView.Coordinator, textView: NoteTextView, window: NSWindow) {
        let view = view(
            for: input,
            onSourceChange: onSourceChange,
            onHeightChange: onHeightChange)
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = NoteTextView(usingTextLayoutManager: true)
        NoteEditorView.configure(textView)
        textView.delegate = coordinator
        textView.editorUndoManager = coordinator.editorUndoManager
        textView.setFrameSize(NSSize(width: 320, height: 1))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        scrollView.documentView = textView
        let window = NSWindow(
            contentRect: scrollView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.contentView = scrollView
        coordinator.textView = textView
        coordinator.observeUsageBounds()
        coordinator.install(input, resetUndo: false)
        coordinator.reportHeight()
        window.makeFirstResponder(textView)
        return (coordinator, textView, window)
    }

    private static func view(
        for input: NoteEditorInput,
        onSourceChange: @escaping (String) -> Void = { _ in },
        onHeightChange: @escaping (NoteEditorInput, CGFloat) -> Void = { _, _ in }
    ) -> NoteEditorView {
        NoteEditorView(
            input: input,
            onSourceChange: onSourceChange,
            onContentHeightChange: onHeightChange,
            onReady: { _ in })
    }

    private static func check(_ message: String, _ condition: @autoclosure () -> Bool) {
        guard condition() else {
            failures += 1
            print("FAIL: \(message)")
            return
        }
    }
}
