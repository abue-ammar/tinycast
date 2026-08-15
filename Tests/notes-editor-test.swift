import AppKit
import Foundation
import SwiftUI

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
        testHostedEditorUsesPanelWidthForInitialHeight()
        testLiveHeightShrinksAfterDeletion()
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
        let trailingLine = NoteEditorView.contentHeight(for: "Short\n", width: 320)
        let empty = NoteEditorView.contentHeight(for: "", width: 320)
        let wrapped = NoteEditorView.contentHeight(
            for: String(repeating: "A long wrapped paragraph. ", count: 80),
            width: 320)
        let long = NoteEditorView.contentHeight(
            for: (0..<80).map { "Line \($0) with enough literal text to wrap" }
                .joined(separator: "\n"),
            width: 320)
        check("an empty editor retains one caret line", empty == short)
        check("a trailing newline contributes its empty line", trailingLine > short)
        check("a wrapped paragraph contributes its complete fragment height", wrapped > short)
        check("literal editor height grows with laid-out content", long > short)
        let longEditor = makeEditor(
            input: NoteEditorInput(
                id: NoteID(rawValue: "Fragment Reference.md"),
                source: String(repeating: "Paragraph long enough to wrap. ", count: 200),
                epoch: 1))
        check(
            "terminal-fragment height matches exhaustive fragment measurement",
            NoteEditorView.contentHeight(for: longEditor.textView.string, width: 320)
                == exhaustiveHeight(of: longEditor.textView))
        check(
            "Markdown markers receive no rendered height treatment",
            NoteEditorView.contentHeight(for: "**plain**", width: 320)
                == NoteEditorView.contentHeight(for: "123456789", width: 320))
    }

    private static func testHostedEditorUsesPanelWidthForInitialHeight() {
        let source = String(repeating: "A long wrapped paragraph. ", count: 80)
        let input = NoteEditorInput(
            id: NoteID(rawValue: "Hosted.md"),
            source: source,
            epoch: 1)
        var heights: [CGFloat] = []
        let hostingView = NSHostingView(
            rootView: NoteEditorView(
                input: input,
                onSourceChange: { _ in },
                onContentHeightChange: { _, height in heights.append(height) },
                onReady: { _ in }))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(x: 0, y: 0, width: Theme.Size.noteWidth, height: 220)
        hostingView.layoutSubtreeIfNeeded()

        check(
            "the hosted editor initially measures wrapped content at the panel width",
            heights.first == NoteEditorView.contentHeight(for: source, width: Theme.Size.noteWidth))
    }

    private static func testLiveHeightShrinksAfterDeletion() {
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
        let expectedHeight = exhaustiveHeight(of: editor.textView)
        let deletionHeights = heights.dropFirst(reportsBeforeDeletion)

        check("live editing expands the measured editor height", expandedHeight > 0)
        check(
            "deleting rows publishes one immediate height",
            deletionHeights.count == 1)
        check(
            "deleting rows immediately reports the exact clean-layout height",
            deletionHeights.last == expectedHeight)
    }

    private static func exhaustiveHeight(of textView: NSTextView) -> CGFloat {
        guard let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return Theme.Size.noteEditorInset * 2 }
        layoutManager.ensureLayout(for: contentManager.documentRange)
        var extent: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: contentManager.documentRange.location,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            extent = max(extent, fragment.layoutFragmentFrame.maxY)
            return true
        }
        return ceil(extent + textView.textContainerInset.height * 2)
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
