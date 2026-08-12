import AppKit
import Foundation

@main
@MainActor
struct NotesEditorTests {
    private static var failures = 0

    static func main() {
        _ = NSApplication.shared
        testProjectedEditingAndUndoIsolation()
        testCanonicalCopyAndCut()
        testCaretAnchoringAcrossProjectionChanges()
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

        window.makeFirstResponder(textView)
        textView.setSelectedRange(
            NSRange(location: (textView.string as NSString).length, length: 0))
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        coordinator.noteTextView(textView, perform: .link)
        check("link insertion reveals its editable literal source", textView.string.hasSuffix("[text](url)"))
        check(
            "link insertion selects the destination placeholder",
            (textView.string as NSString).substring(with: textView.selectedRange()) == "url")

        let headingInput = NoteEditorInput(
            id: NoteID(rawValue: "Heading.md"),
            source: "# **Bold** heading",
            epoch: 4)
        window.makeFirstResponder(nil)
        coordinator.install(headingInput, resetUndo: true)
        let boldLocation = (textView.string as NSString).range(of: "Bold").location
        let headingFont = textView.textStorage?.attribute(
            .font,
            at: boldLocation,
            effectiveRange: nil) as? NSFont
        check(
            "bold text inside a heading keeps the heading size",
            headingFont?.pointSize == NSFont.preferredFont(forTextStyle: .title1).pointSize)
        check(
            "bold text inside a heading keeps its bold trait",
            headingFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        let listInput = NoteEditorInput(
            id: NoteID(rawValue: "List.md"),
            source: "- item",
            epoch: 5)
        coordinator.install(listInput, resetUndo: true)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        textView.insertNewline(nil)
        check("native Return continues a canonical Markdown list", changes.last == "- item\n- ")
        coordinator.editorUndoManager.undo()
        check("list continuation undoes in one step", changes.last == "- item")

        let blockInput = NoteEditorInput(
            id: NoteID(rawValue: "Blocks.md"),
            source: "> Quote\n- item\n```\ncode\n```\n---\n#### Four\n##### Five\n###### Six",
            epoch: 6)
        window.makeFirstResponder(nil)
        coordinator.install(blockInput, resetUndo: true)
        let blockText = textView.string as NSString
        let quoteStyle = textView.textStorage?.attribute(
            .paragraphStyle,
            at: blockText.range(of: "Quote").location,
            effectiveRange: nil) as? NSParagraphStyle
        check("blockquotes carry a leading-rule text block", quoteStyle?.textBlocks.isEmpty == false)
        let listStyle = textView.textStorage?.attribute(
            .paragraphStyle,
            at: blockText.range(of: "item").location,
            effectiveRange: nil) as? NSParagraphStyle
        check("list wrapping uses a hanging indent", (listStyle?.headIndent ?? 0) > 0)
        let codeStyle = textView.textStorage?.attribute(
            .paragraphStyle,
            at: blockText.range(of: "code").location,
            effectiveRange: nil) as? NSParagraphStyle
        check(
            "fenced code carries a block surface",
            codeStyle?.textBlocks.first?.backgroundColor != nil)
        let headingFonts = ["Four", "Five", "Six"].compactMap { value in
            textView.textStorage?.attribute(
                .font,
                at: blockText.range(of: value).location,
                effectiveRange: nil) as? NSFont
        }
        check(
            "H4 through H6 keep a descending hierarchy",
            headingFonts.count == 3
                && headingFonts[0].pointSize > headingFonts[1].pointSize
                && headingFonts[1].pointSize > headingFonts[2].pointSize)
    }

    private static func testCaretAnchoringAcrossProjectionChanges() {
        let destination = String(repeating: "segment/", count: 80)
        let source = (0..<30).map { "Line \($0)" }.joined(separator: "\n")
            + "\n[label](https://example.com/\(destination)) trailing\n"
            + (31..<60).map { "Line \($0)" }.joined(separator: "\n")
        let input = NoteEditorInput(
            id: NoteID(rawValue: "Anchoring.md"),
            source: source,
            epoch: 1)
        let view = NoteEditorView(
            input: input,
            onSourceChange: { _ in },
            onContentHeightChange: { _ in },
            onReady: { _ in },
            onOpenLink: { _ in })
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = NoteTextView(usingTextLayoutManager: true)
        textView.editorActions = coordinator
        textView.editorUndoManager = coordinator.editorUndoManager
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.setFrameSize(NSSize(width: 320, height: 1))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 140))
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

        let labelRange = (textView.string as NSString).range(of: "label")
        let caret = NSRange(location: NSMaxRange(labelRange), length: 0)
        textView.setSelectedRange(caret)
        textView.scrollRangeToVisible(caret)
        let before = textView.firstRect(forCharacterRange: caret, actualRange: nil)
        coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        let after = textView.firstRect(
            forCharacterRange: textView.selectedRange(),
            actualRange: nil)
        check(
            "revealing Markdown keeps the caret anchored in the viewport",
            before.height > 0 && after.height > 0 && abs(before.midY - after.midY) < 1)
    }

    private static func testCanonicalCopyAndCut() {
        let source = "# Heading\n\n**bold**"
        var changes: [String] = []
        let input = NoteEditorInput(
            id: NoteID(rawValue: "Copy.md"),
            source: source,
            epoch: 1)
        let view = NoteEditorView(
            input: input,
            onSourceChange: { changes.append($0) },
            onContentHeightChange: { _ in },
            onReady: { _ in },
            onOpenLink: { _ in })
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = NoteTextView(usingTextLayoutManager: true)
        textView.editorActions = coordinator
        textView.editorUndoManager = coordinator.editorUndoManager
        coordinator.textView = textView
        coordinator.install(input, resetUndo: false)

        let boldRange = (textView.string as NSString).range(of: "bold")
        textView.setSelectedRange(boldRange)
        textView.copy(nil)
        check(
            "copying a complete rendered construct includes its Markdown",
            NSPasteboard.general.string(forType: .string) == "**bold**")
        textView.setSelectedRange(NSRange(location: boldRange.location + 1, length: 2))
        textView.copy(nil)
        check(
            "copying part of rendered text remains character exact",
            NSPasteboard.general.string(forType: .string) == "ol")

        textView.selectAll(nil)
        textView.copy(nil)
        check(
            "Select All and Copy return complete literal Markdown",
            NSPasteboard.general.string(forType: .string) == source)
        textView.cut(nil)
        check("Select All and Cut remove the complete source", changes.last == "")
        check("Select All and Cut leave no hidden prefix behind", textView.string.isEmpty)
        coordinator.editorUndoManager.undo()
        check("canonical Cut undoes in one step", changes.last == source)

        coordinator.install(input, resetUndo: true)
        let renderedBoldRange = (textView.string as NSString).range(of: "bold")
        _ = coordinator.textView(
            textView,
            shouldChangeTextIn: renderedBoldRange,
            replacementString: "plain")
        check(
            "typing over a complete rendered construct removes hidden delimiters",
            changes.last == "# Heading\n\nplain")

        coordinator.install(input, resetUndo: true)
        _ = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(location: renderedBoldRange.location + 1, length: 2),
            replacementString: "")
        check(
            "deleting part of rendered formatting preserves its delimiters",
            changes.last == "# Heading\n\n**bd**")

        coordinator.install(input, resetUndo: true)
        _ = coordinator.textView(
            textView,
            shouldChangeTextIn: NSRange(
                location: 0,
                length: (textView.string as NSString).length),
            replacementString: "Replacement")
        check(
            "typing over Select All replaces every hidden marker",
            changes.last == "Replacement")
    }

    private static func check(_ message: String, _ condition: @autoclosure () -> Bool) {
        guard condition() else {
            failures += 1
            print("FAIL: \(message)")
            return
        }
    }
}
