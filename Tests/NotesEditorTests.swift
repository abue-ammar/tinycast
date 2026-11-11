import AppKit
import Carbon.HIToolbox
import Foundation
import SwiftUI

@main
@MainActor
struct NotesEditorTests {
    private static var failures = 0

    static func main() async {
        _ = NSApplication.shared
        testLiteralEditingAndNativeCommands(rendersMarkdown: false)
        testLiteralEditingAndNativeCommands(rendersMarkdown: true)
        testUndoAndRedoShortcuts(rendersMarkdown: false)
        testUndoAndRedoShortcuts(rendersMarkdown: true)
        testUndoIsolation(afterUndo: false)
        testUndoIsolation(afterUndo: true)
        testQuickActionReplacement()
        testCharacterCountReports()
        testRenderingKeepsSourceAndUndo()
        testHiddenMarkersAndReveal()
        testRestyleFollowsEdits()
        testRenderingOffIsLiteral()
        testTaskSpacing()
        testBlockDecorationsAndFragments()
        testListMarkersWaitForSpace()
        testListKeysAndChords()
        testFormattingReports()
        testTaskRuleCheckboxesAndLinks()
        testTasks()
        testTaskEdits()
        testMarkersFollowAWrappedFirstWord()
        testTextHeight(rendersMarkdown: false)
        testTextHeight(rendersMarkdown: true)
        testHeightBeforeDraw()
        print(failures == 0 ? "Notes editor tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testTextHeight(rendersMarkdown: Bool) {
        let input = NoteEditorInput(id: NoteID(rawValue: "Sizing.md"), source: "", epoch: 0)
        let editor = makeEditor(input: input, rendersMarkdown: rendersMarkdown)
        let emptyHeight = editor.textView.textHeight(upTo: .infinity)
        check(
            "an empty note measures shorter than the visible area", emptyHeight < editor.textView.frame.height
        )

        let lines = String(repeating: "A line of text\n", count: 20)
        editor.textView.insertText(lines, replacementRange: editor.textView.selectedRange())
        let multilineHeight = editor.textView.textHeight(upTo: .infinity)
        check("new lines grow the measured height at once", multilineHeight > emptyHeight)

        let wrappedText = String(repeating: "wrapped words ", count: 80)
        editor.textView.insertText(wrappedText, replacementRange: editor.textView.selectedRange())
        let wrappedHeight = editor.textView.textHeight(upTo: .infinity)
        check("wrapped text grows the measured height without a newline", wrappedHeight > multilineHeight)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        paste("\n" + lines, into: editor.textView, from: pasteboard)
        check("paste grows the measured height", editor.textView.textHeight(upTo: .infinity) > wrappedHeight)

        editor.textView.selectAll(nil)
        editor.textView.deleteBackward(nil)
        check(
            "deleting the text shrinks the measured height back",
            editor.textView.textHeight(upTo: .infinity) == emptyHeight)
    }

    /// The fit reads before any draw, so each height here is read right after its edit returns.
    private static func testHeightBeforeDraw() {
        let mixed = [
            "# Title", "Intro", "", "## Section", "- item", "- [ ] task", "1. one", "> quote", "---", "```",
            "let x = 1", "```", "| a | b |", "| --- | --- |", "| 1 | 2 |", "", "last"
        ].joined(separator: "\n")
        let notes = [
            ("list", "Ideas:\n- First\n- Second\n- Third"), ("mixed", mixed), ("trailing newline", "a\n- b\n")
        ]
        for rendersMarkdown in [true, false] {
            for (name, source) in notes {
                checkHeightBeforeDraw(
                    of: "\(rendersMarkdown ? "rendered" : "literal") \(name) note", source: source,
                    rendersMarkdown: rendersMarkdown)
            }
        }

        let long = makeEditor(
            input: NoteEditorInput(
                id: NoteID(rawValue: "Long.md"), source: String(repeating: "- Item\n", count: 60), epoch: 0),
            rendersMarkdown: true)
        let limit = Theme.Size.noteWindowMaxHeight
        let measured = long.textView.textHeight(upTo: limit)
        check("a note taller than the window still measures past its limit", measured >= limit)
        check(
            "measuring stops near the limit instead of laying out the rest",
            measured < laidOutHeight(of: long.textView))
    }

    private static func checkHeightBeforeDraw(of note: String, source: String, rendersMarkdown: Bool) {
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "Heights.md"), source: source, epoch: 0),
            rendersMarkdown: rendersMarkdown)
        let textView = editor.textView
        let length = { (textView.string as NSString).length }
        func edit(_ name: String, at location: Int? = nil, _ change: () -> Void) {
            if let location { textView.setSelectedRange(NSRange(location: location, length: 0)) }
            change()
            let measured = textView.textHeight(upTo: Theme.Size.noteWindowMaxHeight)
            check(
                "\(name) in a \(note) measures its height before a draw",
                measured == laidOutHeight(of: textView))
        }
        edit("typing at the end", at: length()) {
            textView.insertText("x", replacementRange: textView.selectedRange())
        }
        edit("Return at the end") { textView.insertNewline(nil) }
        edit("Return in the middle", at: length() / 2) { textView.insertNewline(nil) }
        edit("typing in the middle") { textView.insertText("y", replacementRange: textView.selectedRange()) }
        edit("Delete in the middle") { textView.deleteBackward(nil) }
        edit("Delete at a line's start") { textView.deleteBackward(nil) }
        edit("a second Delete there") { textView.deleteBackward(nil) }
        edit("Return at the start", at: 0) { textView.insertNewline(nil) }
        edit("undo") { editor.coordinator.editorUndoManager.undo() }
        edit("switching notes") {
            editor.coordinator.update(
                NoteEditorInput(id: NoteID(rawValue: "Other.md"), source: source, epoch: 0))
        }
        edit("deleting everything") {
            textView.selectAll(nil)
            textView.deleteBackward(nil)
        }
        withExtendedLifetime(editor) {}
    }

    /// Where the last line sits once the whole note is laid out, as a draw would leave it.
    private static func laidOutHeight(of textView: NSTextView) -> CGFloat {
        guard let manager = textView.textLayoutManager else { return -1 }
        manager.ensureLayout(for: manager.documentRange)
        var bottom: CGFloat = 0
        manager.enumerateTextLayoutFragments(from: manager.documentRange.endLocation, options: [.reverse]) {
            bottom = $0.layoutFragmentFrame.maxY
            return false
        }
        return bottom + textView.textContainerInset.height * 2
    }

    private static func testLiteralEditingAndNativeCommands(rendersMarkdown: Bool) {
        let source = "# Heading\n\nThis is **bold** and [linked](https://example.com)."
        let input = NoteEditorInput(
            id: NoteID(rawValue: "Literal.md"),
            source: source,
            epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(
            input: input, rendersMarkdown: rendersMarkdown, onSourceChange: { changes.append($0) })
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        check("the editor displays literal Markdown source", editor.textView.string == source)
        check("the plain editor enables native Find", editor.textView.usesFindBar)
        editor.textView.find(.showFindInterface)
        check("Find opens in the editor", editor.textView.enclosingScrollView?.isFindBarVisible == true)
        editor.textView.find(.hideFindInterface)
        check("Find closes in the editor", editor.textView.enclosingScrollView?.isFindBarVisible == false)
        check("Find closes without changing the source", editor.textView.string == source)

        let boldRange = (editor.textView.string as NSString).range(of: "**bold**")
        editor.textView.setSelectedRange(boldRange)
        copySelection(of: editor.textView, to: pasteboard)
        check(
            "native Copy preserves literal Markdown",
            pasteboard.string(forType: .string) == "**bold**")

        cutSelection(of: editor.textView, to: pasteboard)
        check("native Cut publishes one literal source update", changes.count == 1)
        check("native Cut removes the selected source", !editor.textView.string.contains("**bold**"))
        editor.coordinator.editorUndoManager.undo()
        check("native Undo restores the literal source", editor.textView.string == source)
        editor.coordinator.editorUndoManager.redo()
        check("native Redo restores the cut", editor.textView.string == changes.last)

        let end = (editor.textView.string as NSString).length
        editor.textView.setSelectedRange(NSRange(location: end, length: 0))
        paste(" [literal](url)", into: editor.textView, from: pasteboard)
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

    private static func testQuickActionReplacement() {
        let source = "The cat are here."
        let input = NoteEditorInput(id: NoteID(rawValue: "Action.md"), source: source, epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: input, onSourceChange: { changes.append($0) })
        let range = (source as NSString).range(of: "cat are")
        editor.textView.setSelectedRange(range)
        check("Quick Actions read the note selection", editor.textView.injectableSelection == "cat are")
        check(
            "Quick Actions replace an unchanged note selection",
            editor.textView.replaceUnchangedSelection(
                with: "cats are", source: source, range: range))
        check(
            "replacement updates the note through the editor",
            editor.textView.string == "The cats are here." && changes.last == editor.textView.string)
        editor.coordinator.editorUndoManager.undo()
        check("the replacement is undoable", editor.textView.string == source)

        editor.textView.setSelectedRange(NSRange(location: 0, length: 3))
        check(
            "a moved selection is not replaced",
            !editor.textView.replaceUnchangedSelection(with: "wrong", source: source, range: range))
        editor.textView.insertText("!", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.setSelectedRange(range)
        check(
            "a changed note is not replaced",
            !editor.textView.replaceUnchangedSelection(with: "wrong", source: source, range: range))
    }

    private static func testUndoAndRedoShortcuts(rendersMarkdown: Bool) {
        let source = "# Heading\n🧑🏽‍💻e\u{301}"
        let input = NoteEditorInput(id: NoteID(rawValue: "Undo.md"), source: source, epoch: 1)
        var changes: [String] = []
        var counts: [Int] = []
        let editor = makeEditor(
            input: input, rendersMarkdown: rendersMarkdown,
            onSourceChange: { changes.append($0) }, onCountChange: { _, count in counts.append(count) })
        let undo = keyDown("z", keyCode: kVK_ANSI_Z, in: editor.window)
        let redo = keyDown("Z", keyCode: kVK_ANSI_Z, modifiers: [.command, .shift], in: editor.window)
        editor.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        editor.textView.insertText(" edit", replacementRange: editor.textView.selectedRange())
        check("⌘Z reaches the editor through its window", editor.window.performKeyEquivalent(with: undo))
        check("⌘Z restores exact source", editor.textView.string == source)
        check("Undo publishes the restored source for autosave", changes == [source + " edit", source])
        check("Undo updates the character count", counts.last == (source as NSString).length)
        check("⌘⇧Z reaches the editor through its window", editor.window.performKeyEquivalent(with: redo))
        check("⌘⇧Z restores the edit", editor.textView.string == source + " edit")
        check("Redo publishes the restored edit for autosave", changes.last == source + " edit")
        check("Redo updates the character count", counts.last == ((source + " edit") as NSString).length)

        editor.coordinator.editorUndoManager.undo()
        check("native Undo also publishes the source", changes.last == source)
        editor.coordinator.editorUndoManager.redo()
        check("native Redo also publishes the source", changes.last == source + " edit")
        _ = editor.window.performKeyEquivalent(with: undo)
        editor.textView.insertText(" new", replacementRange: editor.textView.selectedRange())
        check("an edit after Undo discards Redo", !editor.coordinator.editorUndoManager.canRedo)
        let updated = editor.textView.string
        let changeCount = changes.count
        let repeatedUndo = keyDown("z", keyCode: kVK_ANSI_Z, isARepeat: true, in: editor.window)
        check("a held Undo shortcut is consumed", editor.window.performKeyEquivalent(with: repeatedUndo))
        check("a held Undo shortcut does not repeat", editor.textView.string == updated)
        for modifiers: NSEvent.ModifierFlags in [[.command, .option], [.command, .control]] {
            let event = keyDown("z", keyCode: kVK_ANSI_Z, modifiers: modifiers, in: editor.window)
            check("other Z chords leave history alone", !editor.textView.performKeyEquivalent(with: event))
        }
        editor.window.makeFirstResponder(nil)
        check("an unfocused editor does not claim Undo", !editor.textView.performKeyEquivalent(with: undo))
        check(
            "unrelated shortcuts change nothing",
            editor.textView.string == updated && changes.count == changeCount)
        editor.window.makeFirstResponder(editor.textView)
        check("empty Redo is handled locally", editor.window.performKeyEquivalent(with: redo))
        check("empty Redo changes nothing", editor.textView.string == updated && changes.count == changeCount)

        editor.coordinator.update(NoteEditorInput(id: input.id, source: updated, epoch: input.epoch))
        check("a source echo preserves Undo", editor.coordinator.editorUndoManager.canUndo)
        _ = editor.window.performKeyEquivalent(with: undo)
        check("Undo after a source echo still restores the note", editor.textView.string == source)
        check("Undo after a source echo still publishes the note", changes.last == source)
        let restoredChangeCount = changes.count
        check("empty Undo is handled locally", editor.window.performKeyEquivalent(with: undo))
        check("empty Undo publishes nothing", changes.count == restoredChangeCount)
    }

    private static func testUndoIsolation(afterUndo: Bool) {
        let first = NoteEditorInput(
            id: NoteID(rawValue: "First.md"),
            source: "First",
            epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: first, onSourceChange: { changes.append($0) })
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.textView.insertText(" edit", replacementRange: editor.textView.selectedRange())
        check("native editing registers Undo", editor.coordinator.editorUndoManager.canUndo)
        if afterUndo {
            editor.coordinator.editorUndoManager.undo()
            check("native Undo registers Redo", editor.coordinator.editorUndoManager.canRedo)
        }

        let second = NoteEditorInput(
            id: NoteID(rawValue: "Second.md"),
            source: "Second",
            epoch: 2)
        editor.coordinator.parent = view(for: second, onSourceChange: { changes.append($0) })
        editor.coordinator.update(second)
        check("switching notes installs the replacement source", editor.textView.string == "Second")
        check("switching notes clears stale Undo", !editor.coordinator.editorUndoManager.canUndo)
        check("switching notes clears stale Redo", !editor.coordinator.editorUndoManager.canRedo)
        editor.coordinator.editorUndoManager.undo()
        editor.coordinator.editorUndoManager.redo()
        check("Undo after a switch leaves the new note intact", editor.textView.string == "Second")

        editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        editor.textView.insertText(" draft", replacementRange: editor.textView.selectedRange())
        let external = NoteEditorInput(id: second.id, source: "External", epoch: 3)
        editor.coordinator.parent = view(for: external, onSourceChange: { changes.append($0) })
        editor.coordinator.update(external)
        check("a clean external reload replaces the displayed source", editor.textView.string == "External")
        check("a clean external reload clears stale Undo", !editor.coordinator.editorUndoManager.canUndo)
        check("a clean external reload clears stale Redo", !editor.coordinator.editorUndoManager.canRedo)
    }

    private static func testCharacterCountReports() {
        let first = NoteEditorInput(id: NoteID(rawValue: "First.md"), source: "First", epoch: 1)
        var reports: [(NoteEditorInput, Int)] = []
        let editor = makeEditor(input: first, onCountChange: { reports.append(($0, $1)) })
        check("installing a note reports its length", reports.last?.1 == 5)

        editor.textView.selectAll(nil)
        editor.textView.insertText("Twelve chars", replacementRange: editor.textView.selectedRange())
        check("typing reports the new length", reports.last?.1 == 12)

        editor.textView.selectAll(nil)
        editor.textView.insertText("🇬🇧", replacementRange: editor.textView.selectedRange())
        check(
            "the count is the text storage's own UTF-16 length",
            reports.last?.1 == editor.textView.textStorage?.length)

        let second = NoteEditorInput(id: NoteID(rawValue: "Second.md"), source: "Second", epoch: 2)
        editor.coordinator.parent = view(for: second, onCountChange: { reports.append(($0, $1)) })
        editor.coordinator.update(second)
        check(
            "a stale count cannot be attributed to the replacement note",
            reports.last?.0.id == second.id && reports.last?.1 == 6)
    }

    private static let everyConstruct = """
        # Heading
        Some **bold**, _italic_, ~~gone~~, `code` and [a link](https://example.com) or https://a.com.
        - bullet
            - nested
        1. first
        - [ ] open task
        - [x] done task
        > quoted
        ---
        ```swift
        let x = 1
        ```
        """

    private static func testRenderingKeepsSourceAndUndo() {
        let input = NoteEditorInput(id: NoteID(rawValue: "All.md"), source: everyConstruct, epoch: 1)
        var changes: [String] = []
        let editor = makeEditor(input: input, rendersMarkdown: true, onSourceChange: { changes.append($0) })
        let undo = editor.coordinator.editorUndoManager
        check("rendering leaves the source byte for byte", editor.textView.string == everyConstruct)
        check("rendering on install registers no Undo", !undo.canUndo)

        editor.textView.setSelectedRange(NSRange(location: (everyConstruct as NSString).length, length: 0))
        check("a selection-driven restyle registers no Undo", !undo.canUndo && changes.isEmpty)

        editor.coordinator.setRendersMarkdown(false)
        editor.coordinator.setRendersMarkdown(true)
        check(
            "toggling rendering keeps the source and registers no Undo",
            editor.textView.string == everyConstruct && !undo.canUndo && changes.isEmpty)

        editor.textView.insertText("!", replacementRange: editor.textView.selectedRange())
        editor.textView.insertText("?", replacementRange: editor.textView.selectedRange())
        check(
            "each edit publishes once, equal to the displayed source",
            changes.count == 2 && changes.last == editor.textView.string)
    }

    private static func testHiddenMarkersAndReveal() {
        let source = "Title\n\nplain **bold** text"
        let input = NoteEditorInput(id: NoteID(rawValue: "Reveal.md"), source: source, epoch: 1)
        let editor = makeEditor(input: input, rendersMarkdown: true)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let marker = (source as NSString).range(of: "**").location
        let content = (source as NSString).range(of: "bold").location
        check("a rendered marker is hidden", font(in: editor.textView, at: marker)?.pointSize == 0.01)
        check(
            "rendered emphasis is bold",
            font(in: editor.textView, at: content)?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        editor.textView.setSelectedRange(NSRange(location: content, length: 0))
        let revealedColor = color(in: editor.textView, at: marker)
        check(
            "the caret's line shows its markers at body size in a dimmed colour",
            font(in: editor.textView, at: marker)?.pointSize == NoteMarkdownTypography.body.pointSize
                && revealedColor != nil && revealedColor != NSColor.clear
                && revealedColor != color(in: editor.textView, at: content))

        let heading = NoteEditorInput(id: NoteID(rawValue: "Heading.md"), source: "# Big\n\nbody", epoch: 2)
        editor.coordinator.update(heading)
        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        editor.textView.setSelectedRange(NSRange(location: 8, length: 0))
        let typing = editor.textView.typingAttributes
        check(
            "typing attributes return to the body style after leaving a heading",
            typing[.font] as? NSFont == NoteMarkdownTypography.body
                && typing.count == NoteMarkdownStyler.literal.count)

        editor.window.makeFirstResponder(nil)
        check(
            "an unfocused editor reveals nothing",
            editor.coordinator.renderer.revealed.isEmpty
                && font(in: editor.textView, at: 0)?.pointSize == 0.01)
    }

    private static func testRestyleFollowsEdits() {
        let source = "top\nplain **b**\nend"
        let input = NoteEditorInput(id: NoteID(rawValue: "Fence.md"), source: source, epoch: 1)
        let editor = makeEditor(input: input, rendersMarkdown: true)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.textView.insertText("```\n", replacementRange: NSRange(location: 0, length: 0))
        let bold = (editor.textView.string as NSString).range(of: "**b**").location
        check(
            "opening a fence above text restyles the lines below as code",
            font(in: editor.textView, at: bold) == NoteMarkdownTypography.codeBlock
                && decoration(in: editor.textView, at: bold) != nil)

        editor.textView.setSelectedRange(NSRange(location: 4, length: 0))
        editor.textView.deleteBackward(nil)
        editor.textView.deleteBackward(nil)
        editor.textView.deleteBackward(nil)
        editor.textView.deleteBackward(nil)
        let restored = (editor.textView.string as NSString).range(of: "**b**").location
        check(
            "closing the fence restores them",
            editor.textView.string == source && decoration(in: editor.textView, at: restored) == nil
                && font(in: editor.textView, at: restored)?.pointSize == 0.01)

        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editor.textView.insertText("- ", replacementRange: NSRange(location: 0, length: 0))
        editor.textView.setSelectedRange(
            NSRange(location: (editor.textView.string as NSString).length, length: 0))
        check("a new list line renders once the caret leaves", decoration(in: editor.textView, at: 0) != nil)
        editor.coordinator.editorUndoManager.undo()
        check(
            "Undo, which posts no text change, still restyles",
            editor.textView.string == source && decoration(in: editor.textView, at: 0) == nil)

        let rows = "intro\n| `a` | **b** |\n| `c` | d |\n| e | f |\n| g | h |\n| i | j |\nend"
        editor.coordinator.update(NoteEditorInput(id: input.id, source: rows, epoch: 2))
        let lastRow = { (editor.textView.string as NSString).range(of: "| i").location }
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        check(
            "pipe rows without a delimiter row render inline styles",
            font(in: editor.textView, at: (rows as NSString).range(of: "`a`").location)?.pointSize == 0.01)
        let delimiterAt = (rows as NSString).range(of: "| `c`").location
        editor.textView.setSelectedRange(NSRange(location: delimiterAt, length: 0))
        editor.textView.insertText("| --- | --- |\n", replacementRange: editor.textView.selectedRange())
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let code = (editor.textView.string as NSString).range(of: "`a`").location
        check(
            "typing a delimiter row turns every row into a literal monospaced table",
            font(in: editor.textView, at: code) == NoteMarkdownTypography.codeBlock
                && font(in: editor.textView, at: lastRow()) == NoteMarkdownTypography.codeBlock
                && editor.textView.string.contains("| `c` | d |"))
    }

    private static func testRenderingOffIsLiteral() {
        let input = NoteEditorInput(id: NoteID(rawValue: "Off.md"), source: everyConstruct, epoch: 1)
        let editor = makeEditor(input: input, rendersMarkdown: true)
        editor.coordinator.setRendersMarkdown(false)
        var literal = true
        let storage = editor.textView.textStorage ?? NSTextStorage()
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, _, _ in
            literal =
                literal && attributes.count == 2
                && attributes[.font] as? NSFont == NoteMarkdownTypography.body
                && attributes[.noteBlockDecoration] == nil
        }
        check("rendering off leaves exactly the literal attributes", literal)
        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        check("rendering off never reveals or parses", editor.coordinator.renderer.markdown.lines.isEmpty)
    }

    private static func testTaskSpacing() {
        let source = "- [ ] first\n- [x] second\nplain\n```\n- [ ] code\n```"
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "Spacing.md"), source: source, epoch: 1),
            rendersMarkdown: true)
        let text = source as NSString
        editor.textView.setSelectedRange(NSRange(location: text.length, length: 0))
        func style(at location: Int) -> NSParagraphStyle? {
            editor.textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil)
                as? NSParagraphStyle
        }
        let fragments = layoutFragments(in: editor.textView)
        let second = text.range(of: "- [x] second").location
        if let top = fragments[0], let bottom = fragments[second] {
            let box = { (fragment: NSTextLayoutFragment) -> CGRect in
                let line = (fragment as? NoteBlockLayoutFragment)?.firstLine ?? .zero
                return NoteCheckboxGeometry.rect(
                    level: 0, firstLineHeight: line.height,
                    bodyPointSize: NoteMarkdownTypography.body.pointSize
                ).offsetBy(dx: 0, dy: fragment.layoutFragmentFrame.minY + line.minY)
            }
            check("task checkboxes have breathing room", box(bottom).minY - box(top).maxY >= Theme.Spacing.md)
        } else {
            check("task checkboxes have breathing room", false)
        }
        for location in [0, second] {
            check(
                "task spacing belongs to its paragraph",
                style(at: location)?.paragraphSpacing == Theme.Spacing.md)
            check("wrapped task lines retain native spacing", style(at: location)?.lineSpacing == 0)
        }
        let lists = "- one\n- two\n1. three\n2. four"
        editor.coordinator.update(NoteEditorInput(id: NoteID(rawValue: "Lists.md"), source: lists, epoch: 2))
        editor.textView.setSelectedRange(NSRange(location: (lists as NSString).length, length: 0))
        check(
            "bullets and numbered items get the same spacing as tasks",
            [0, 6, 12].allSatisfy { style(at: $0)?.paragraphSpacing == Theme.Spacing.md })
        let emptyBullet = "- first\n- \n- third"
        editor.coordinator.update(
            NoteEditorInput(id: NoteID(rawValue: "EmptyBullet.md"), source: emptyBullet, epoch: 3))
        editor.textView.setSelectedRange(NSRange(location: 14, length: 0))
        let bulletFragments = layoutFragments(in: editor.textView)
        check(
            "an empty bullet keeps the filled bullet's line height",
            bulletFragments[8]?.textLineFragments.first?.typographicBounds.height
                == bulletFragments[0]?.textLineFragments.first?.typographicBounds.height)
        check(
            "an empty bullet keeps its dot",
            decoration(in: editor.textView, at: 8)?.shape == .bullet(level: 0))
        check(
            "an empty bullet keeps normal text metrics",
            font(in: editor.textView, at: 8) == NoteMarkdownTypography.body)
        check("an empty bullet keeps list spacing", style(at: 8)?.paragraphSpacing == Theme.Spacing.md)
        editor.textView.setSelectedRange(NSRange(location: 10, length: 0))
        check(
            "an active empty bullet keeps its dot",
            decoration(in: editor.textView, at: 8)?.shape == .bullet(level: 0))
        editor.coordinator.update(
            NoteEditorInput(id: NoteID(rawValue: "Spacing.md"), source: source, epoch: 4))
        editor.textView.setSelectedRange(NSRange(location: text.length, length: 0))
        check(
            "non-list paragraphs retain native spacing",
            style(at: text.range(of: "plain").location) == nil
                && style(at: text.range(of: "- [ ] code").location)?.paragraphSpacing == 0)
        editor.textView.setSelectedRange(NSRange(location: 3, length: 0))
        check("a revealed task keeps its spacing", style(at: 0)?.paragraphSpacing == Theme.Spacing.md)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 6))
        editor.textView.insertText("", replacementRange: editor.textView.selectedRange())
        check("removing a task marker removes its spacing", style(at: 0) == nil)
        editor.coordinator.editorUndoManager.undo()
        check("undo restores task source without adding blank lines", editor.textView.string == source)
    }

    private static func testBlockDecorationsAndFragments() {
        let input = NoteEditorInput(id: NoteID(rawValue: "Blocks.md"), source: everyConstruct, epoch: 1)
        let editor = makeEditor(input: input, rendersMarkdown: true)
        let text = everyConstruct as NSString
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        func shape(_ needle: String) -> NoteBlockDecoration.Shape? {
            let lineStart = text.lineRange(for: text.range(of: needle)).location
            return decoration(in: editor.textView, at: lineStart)?.shape
        }
        check("a bullet carries its decoration", shape("- bullet") == .bullet(level: 0))
        check("a nested bullet carries its level", shape("    - nested") == .bullet(level: 1))
        check("an ordered item carries its own label", shape("1. first") == .ordered(level: 0, label: "1."))
        check("a task carries its state", shape("- [x] done") == .task(level: 0, checked: true))
        check("a quote carries its depth", shape("> quoted") == .quote(depth: 1))
        check("a rule carries its decoration", shape("---") == .rule)
        check("a fence opens a code band", shape("```swift") == .code(.top, language: "swift"))
        check("a code line sits in the band", shape("let x") == .code(.middle, language: nil))
        check("a paragraph carries none", shape("Some") == nil)

        let bullet = text.range(of: "- bullet").location
        var gray: CGColor?
        editor.textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            gray = NSColor(Theme.Colors.textSecondary).cgColor
        }
        check(
            "list markers are a neutral gray",
            decoration(in: editor.textView, at: bullet)?.fill.cgColor == gray)
        let ordered = text.range(of: "1. first").location
        editor.textView.setSelectedRange(NSRange(location: ordered + 4, length: 0))
        check(
            "a number keeps the same gray under the caret",
            color(in: editor.textView, at: ordered)?.cgColor == gray)
        let task = text.range(of: "- [ ] open").location
        editor.textView.setSelectedRange(NSRange(location: task + 6, length: 0))
        check(
            "a task marker keeps the same gray under the caret",
            color(in: editor.textView, at: task)?.cgColor == gray)
        let renderedIndent = paragraphStyle(in: editor.textView, at: bullet)?.headIndent
        editor.textView.setSelectedRange(NSRange(location: bullet + 3, length: 0))
        check("a bullet keeps its dot under the caret", shape("- bullet") == .bullet(level: 0))
        let revealed = paragraphStyle(in: editor.textView, at: bullet)
        check(
            "a bullet keeps its rendered indent under the caret",
            revealed?.headIndent == renderedIndent
                && revealed?.firstLineHeadIndent == renderedIndent)
        editor.textView.setSelectedRange(NSRange(location: text.range(of: "nested").location, length: 0))
        check(
            "moving the caret between bullets keeps both dots",
            shape("- bullet") == .bullet(level: 0)
                && shape("    - nested") == .bullet(level: 1))
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))

        let fragments = layoutFragments(in: editor.textView)
        func fragment(_ needle: String) -> NSTextLayoutFragment? {
            fragments[text.lineRange(for: text.range(of: needle)).location]
        }
        let blockLines = ["- bullet", "1. first", "- [ ] open", "> quoted", "---", "```swift", "let x"]
        check(
            "block lines lay out through the drawing fragment",
            blockLines.allSatisfy { fragment($0) is NoteBlockLayoutFragment })
        check("a paragraph lays out as a plain fragment", !(fragment("Some") is NoteBlockLayoutFragment))

        let width = editor.textView.textContainer?.size.width ?? 0
        let nested = fragment("    - nested")
        check(
            "a nested item's drawing surface reaches back to the container edge",
            (nested?.renderingSurfaceBounds.minX ?? 0) <= -2 * Theme.Size.markdownListMarker
                && (nested?.renderingSurfaceBounds.width ?? 0) >= width)
        let fenceFrame = fragment("```swift")?.layoutFragmentFrame
        let codeFrame = fragment("let x")?.layoutFragmentFrame
        check(
            "consecutive code rows abut with no seam",
            fenceFrame != nil && fenceFrame?.maxY == codeFrame?.minY)
        if let task = fragment("- [ ] open") as? NoteBlockLayoutFragment {
            let firstLine = task.firstLine
            let box = NoteCheckboxGeometry.rect(
                level: 0, firstLineHeight: firstLine.height,
                bodyPointSize: NoteMarkdownTypography.body.pointSize)
            let surface = task.renderingSurfaceBounds.offsetBy(dx: task.layoutFragmentFrame.minX, dy: 0)
            check("the checkbox lies inside the task's drawing surface", surface.contains(box))
        } else {
            check("the checkbox lies inside the task's drawing surface", false)
        }
    }

    private static func testListMarkersWaitForSpace() {
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "ListMarkers.md"), source: "", epoch: 1),
            rendersMarkdown: true)
        editor.textView.insertText("-", replacementRange: editor.textView.selectedRange())
        check("a lone dash stays literal", editor.coordinator.renderer.markdown.lines[0].kind == .paragraph)
        editor.textView.insertText(" ", replacementRange: editor.textView.selectedRange())
        check(
            "space turns a dash into a bullet",
            editor.coordinator.renderer.markdown.lines[0].kind == .bullet
                && decoration(in: editor.textView, at: 0)?.shape == .bullet(level: 0))

        editor.coordinator.update(NoteEditorInput(id: NoteID(rawValue: "Numbered.md"), source: "", epoch: 2))
        editor.textView.insertText("1.", replacementRange: editor.textView.selectedRange())
        check(
            "a lone number marker stays literal",
            editor.coordinator.renderer.markdown.lines[0].kind == .paragraph)
        editor.textView.insertText(" ", replacementRange: editor.textView.selectedRange())
        check(
            "space turns a number marker into a list",
            editor.coordinator.renderer.markdown.lines[0].kind == .ordered(number: 1))
    }

    private static func testListKeysAndChords() {
        var changes: [String] = []
        let input = NoteEditorInput(id: NoteID(rawValue: "Keys.md"), source: "- item", epoch: 1)
        let editor = makeEditor(input: input, rendersMarkdown: true, onSourceChange: { changes.append($0) })
        let undo = editor.coordinator.editorUndoManager
        editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
        editor.textView.insertNewline(nil)
        check(
            "Return continues a list in one published edit",
            editor.textView.string == "- item\n- " && changes == ["- item\n- "]
                && editor.textView.selectedRange() == NSRange(location: 9, length: 0))
        check(
            "a new empty bullet is drawn at the end of a note",
            decoration(in: editor.textView, at: 7)?.shape == .bullet(level: 0))
        undo.undo()
        check("one Undo step removes the continuation", editor.textView.string == "- item")
        undo.redo()

        editor.textView.insertTab(nil)
        check("Tab nests a list line", editor.textView.string == "- item\n    - ")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let paragraph = NoteEditorInput(id: NoteID(rawValue: "Tab.md"), source: "plain", epoch: 2)
        editor.coordinator.update(paragraph)
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.textView.insertTab(nil)
        check("Tab in a paragraph inserts a tab", editor.textView.string == "plain\t")

        let chord = NoteEditorInput(id: NoteID(rawValue: "Chord.md"), source: "make bold", epoch: 3)
        editor.coordinator.update(chord)
        editor.textView.setSelectedRange(NSRange(location: 5, length: 4))
        check(
            "⌘B wraps the selection and claims the chord",
            editor.textView.performKeyEquivalent(with: keyDown("b", keyCode: kVK_ANSI_B, in: editor.window))
                && editor.textView.string == "make **bold**")
        undo.undo()
        check("⌘B undoes in one step", editor.textView.string == "make bold")
        editor.textView.setSelectedRange(NSRange(location: 0, length: 4))
        _ = editor.textView.performKeyEquivalent(
            with: keyDown("8", keyCode: kVK_ANSI_8, modifiers: [.command, .shift], in: editor.window))
        check("⇧⌘8 matches its digit by key code", editor.textView.string == "- make bold")

        let block = NoteEditorInput(id: NoteID(rawValue: "Block.md"), source: "code", epoch: 4)
        editor.coordinator.update(block)
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        check(
            "⌥⌘C fences the line and claims the chord",
            editor.textView.performKeyEquivalent(
                with: keyDown("c", keyCode: kVK_ANSI_C, modifiers: [.command, .option], in: editor.window))
                && editor.textView.string == "```\ncode\n```")
        undo.undo()
        check("⌥⌘C undoes in one step", editor.textView.string == "code")
        check(
            "⇧⌘B quotes the line and claims the chord",
            editor.textView.performKeyEquivalent(
                with: keyDown("B", keyCode: kVK_ANSI_B, modifiers: [.command, .shift], in: editor.window))
                && editor.textView.string == "> code")
        undo.undo()

        editor.coordinator.setRendersMarkdown(false)
        let literal = editor.textView.string
        editor.textView.setSelectedRange(NSRange(location: 2, length: 4))
        let claimed = editor.textView.performKeyEquivalent(
            with: keyDown("b", keyCode: kVK_ANSI_B, in: editor.window))
        check(
            "with rendering off ⌘B is not a formatting chord", !claimed && editor.textView.string == literal)
        editor.textView.setSelectedRange(NSRange(location: (literal as NSString).length, length: 0))
        editor.textView.insertNewline(nil)
        check("with rendering off Return is native", editor.textView.string == literal + "\n")
    }

    private static func testFormattingReports() {
        var reports: [(NoteEditorInput, NoteFormatting)] = []
        let input = NoteEditorInput(id: NoteID(rawValue: "Formatting.md"), source: "plain **bold**", epoch: 1)
        let editor = makeEditor(
            input: input, rendersMarkdown: true, onFormattingChange: { reports.append(($0, $1)) })
        check("install reports formatting", reports.last?.0.id == input.id)

        editor.textView.setSelectedRange(NSRange(location: 10, length: 0))
        check("a caret inside bold reports bold", reports.last?.1.inlineStyles == [.bold])
        editor.textView.setSelectedRange(NSRange(location: 1, length: 0))
        check(
            "a caret in plain text reports a paragraph",
            reports.last?.1.inlineStyles == [] && reports.last?.1.headingLevel == 0)

        editor.textView.format(.toggleQuote)
        check(
            "format(_:) applies the plan and reports the result",
            editor.textView.string == "> plain **bold**" && reports.last?.1.isQuote == true)
        editor.coordinator.editorUndoManager.undo()
        check("format(_:) undoes in one step", editor.textView.string == "plain **bold**")

        editor.coordinator.setRendersMarkdown(false)
        check("rendering off reports plain", reports.last?.1 == .plain)
        editor.textView.format(.toggleQuote)
        check("format(_:) does nothing with rendering off", editor.textView.string == "plain **bold**")
    }

    private static func testTaskRuleCheckboxesAndLinks() {
        var changes: [String] = []
        let input = NoteEditorInput(id: NoteID(rawValue: "Tasks.md"), source: "[]", epoch: 1)
        let editor = makeEditor(input: input, rendersMarkdown: true, onSourceChange: { changes.append($0) })
        editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        editor.textView.insertText(" ", replacementRange: editor.textView.selectedRange())
        check("a space after [] makes a task", editor.textView.string == "- [ ] " && changes.last == "- [ ] ")

        let source = "- [ ] first\n- [ ] second\nend"
        let tasks = NoteEditorInput(id: NoteID(rawValue: "Boxes.md"), source: source, epoch: 2)
        editor.coordinator.update(tasks)
        let caret = NSRange(location: (source as NSString).length, length: 0)
        editor.textView.setSelectedRange(caret)
        let secondStart = (source as NSString).range(of: "- [ ] second").location
        guard let box = checkboxCenter(in: editor.textView, lineStart: secondStart) else {
            return check("the second task lays out a checkbox", false)
        }
        check("clicking a checkbox toggles it", editor.textView.toggleTask(atContainerPoint: box))
        check(
            "the toggle changes one character and leaves the caret and reveal alone",
            editor.textView.string == "- [ ] first\n- [x] second\nend"
                && editor.textView.selectedRange() == caret
                && !editor.coordinator.renderer.revealed.contains(1))
        editor.coordinator.editorUndoManager.undo()
        check("Undo restores the checkbox", editor.textView.string == source)
        check(
            "a click beside the box is not a toggle",
            !editor.textView.toggleTask(atContainerPoint: CGPoint(x: box.x + 60, y: box.y)))

        var opened: [URL] = []
        editor.coordinator.openURL = { opened.append($0) }
        let file = URL(fileURLWithPath: "/etc/hosts")
        _ = editor.coordinator.textView(editor.textView, clickedOnLink: file, at: 0)
        check("a file link never opens", opened.isEmpty)
        let web = URL(string: "https://example.com")
        _ = web.map { editor.coordinator.textView(editor.textView, clickedOnLink: $0, at: 0) }
        check("a web link opens", opened == [web].compactMap { $0 })

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let linkInput = NoteEditorInput(id: NoteID(rawValue: "Paste.md"), source: "see docs", epoch: 3)
        editor.coordinator.update(linkInput)
        editor.textView.setSelectedRange(NSRange(location: 4, length: 4))
        pasteboard.clearContents()
        pasteboard.setString("https://a.com", forType: .string)
        check(
            "pasting a URL over a selection makes a link",
            editor.textView.pasteLink(from: pasteboard)
                && editor.textView.string == "see [docs](https://a.com)")
        pasteboard.clearContents()
        pasteboard.setString("plain words", forType: .string)
        check("pasting other text is not a link", !editor.textView.pasteLink(from: pasteboard))

        let marked = NoteEditorInput(id: NoteID(rawValue: "Marked.md"), source: "**bold**\n- item ", epoch: 4)
        editor.coordinator.update(marked)
        let end = NSRange(location: (marked.source as NSString).length, length: 0)
        editor.textView.setSelectedRange(end)
        editor.textView.setMarkedText(
            "語", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.textView.unmarkText()
        check(
            "marked text beside a rendered line commits exactly",
            editor.textView.string == "**bold**\n- item 語" && changes.last == editor.textView.string
                && font(in: editor.textView, at: 0)?.pointSize == 0.01)
        editor.textView.setMarkedText(
            "語", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.textView.insertNewline(nil)
        check("Return stands down while text is marked", !editor.textView.string.hasSuffix("- "))
    }

    private static func testTasks() {
        let source = "- [ ] 🧑🏽‍💻 first\n* [X] done\n```md\n- [ ] code\n```\n~~~\n- [x] code\n~~~"
        let lines = NoteMarkdownParser.parse(source).lines
        let taskLines = lines.filter { if case .task = $0.kind { true } else { false } }
        check("fenced tasks remain literal", taskLines.count == 2)
        check("uppercase X is checked", taskLines.last?.kind == .task(checked: true))
        check(
            "inline syntax and incomplete markers stay literal",
            NoteMarkdownParser.parse("inline - [ ] task\n- [] task\n- [q] task").lines.allSatisfy {
                if case .task = $0.kind { false } else { true }
            })
        let indented = NoteMarkdownParser.parse("hello\r\n  + [ ] task\r\n").lines
        check(
            "indented CRLF tasks preserve offsets",
            indented.count == 3 && indented[1].checkboxRange == NSRange(location: 11, length: 3))
        check(
            "task content ranges preserve Unicode",
            (source as NSString).substring(with: taskLines[0].contentRange) == "🧑🏽‍💻 first")

        var changes: [String] = []
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "Tasks.md"), source: source, epoch: 1),
            rendersMarkdown: true, onSourceChange: { changes.append($0) })
        check("rendering does not rewrite source", editor.textView.string == source)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        editor.textView.selectAll(nil)
        copySelection(of: editor.textView, to: pasteboard)
        check("copying tasks preserves Markdown", pasteboard.string(forType: .string) == source)

        let caret = NSRange(location: NSMaxRange(taskLines[1].contentRange), length: 0)
        editor.textView.setSelectedRange(caret)
        guard let box = checkboxCenter(in: editor.textView, lineStart: 0) else {
            return check("the first task lays out a checkbox", false)
        }
        check("clicking a checkbox is handled", editor.textView.toggleTask(atContainerPoint: box))
        check("clicking saves checked Markdown", changes.last?.hasPrefix("- [x] ") == true)
        check("clicking preserves the caret", editor.textView.selectedRange() == caret)
        editor.coordinator.editorUndoManager.undo()
        check("checkbox toggle is undoable", editor.textView.string == source)
        editor.coordinator.editorUndoManager.redo()
        check("checkbox toggle is redoable", editor.textView.string.hasPrefix("- [x] "))
        editor.textView.setSelectedRange(NSRange(location: NSMaxRange(taskLines[0].contentRange), length: 0))
        editor.textView.insertNewline(nil)
        check("Return continues with an unchecked task", editor.textView.string.contains("first\n- [ ] \n"))
        editor.textView.insertNewline(nil)
        check("Return on an empty task exits the list", editor.textView.string.contains("first\n\n"))

        editor.textView.selectAll(nil)
        editor.textView.insertText("[]", replacementRange: editor.textView.selectedRange())
        editor.textView.insertText(" ", replacementRange: editor.textView.selectedRange())
        check("bracket-space shortcut creates Markdown", editor.textView.string == "- [ ] ")
        editor.textView.insertText("new", replacementRange: editor.textView.selectedRange())
        check(
            "typing after a checkbox stays visible",
            color(in: editor.textView, at: 6) == NoteMarkdownStyler.literal[.foregroundColor] as? NSColor)
        editor.textView.selectAll(nil)
        editor.textView.insertText("```\n[]", replacementRange: editor.textView.selectedRange())
        editor.textView.insertText(" ", replacementRange: editor.textView.selectedRange())
        check("bracket shortcuts stay literal in code", editor.textView.string == "```\n[] ")
        let replacement = NoteEditorInput(id: NoteID(rawValue: "Other.md"), source: "plain", epoch: 2)
        editor.coordinator.update(replacement)
        check("switching notes clears task undo", !editor.coordinator.editorUndoManager.canUndo)
    }

    private static func testTaskEdits() {
        let source = "- [ ] first\n- [ ]    \n```\n- [ ] literal\n```\n- [x] last"
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "Edits.md"), source: source, epoch: 1),
            rendersMarkdown: true)
        let text = { editor.textView.string as NSString }
        func isTask(_ needle: String) -> Bool {
            let start = text().lineRange(for: text().range(of: needle)).location
            if case .task = decoration(in: editor.textView, at: start)?.shape { return true }
            return false
        }
        editor.textView.setSelectedRange(NSRange(location: 11, length: 0))
        editor.textView.insertText(" longer", replacementRange: editor.textView.selectedRange())
        editor.textView.setSelectedRange(NSRange(location: text().length, length: 0))
        check("typing keeps the other tasks rendered", isTask("- [ ]    ") && !isTask("literal"))
        let literal = text().range(of: "literal")
        editor.textView.insertText("code", replacementRange: literal)
        check("editing fenced text keeps it literal", !isTask("- [ ] code"))
        editor.coordinator.editorUndoManager.undo()
        check("undo preserves fenced text", editor.textView.string.contains("literal"))
        let fence = text().range(of: "```")
        editor.textView.insertText("plain", replacementRange: fence)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        check("changing a fence reparses subsequent tasks", isTask("- [ ] literal"))
        editor.coordinator.editorUndoManager.undo()
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        check("undoing a fence restores subsequent tasks as code", !isTask("- [ ] literal"))
        editor.textView.selectAll(nil)
        editor.textView.insertText("```\n", replacementRange: editor.textView.selectedRange())
        editor.textView.insertText("- [ ] hidden", replacementRange: editor.textView.selectedRange())
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        check("typing at the end of an open fence stays literal", !isTask("hidden"))
    }

    private static func keyDown(
        _ characters: String, keyCode: Int, modifiers: NSEvent.ModifierFlags = [.command],
        isARepeat: Bool = false, in window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: isARepeat, keyCode: UInt16(keyCode))
            ?? NSEvent()
    }

    /// A first word too wide for the line strands the hidden marker on a hairline above it.
    private static func testMarkersFollowAWrappedFirstWord() {
        let word = String(repeating: "wrap", count: 40)
        let source = "- \(word)\n- [ ] \(word)\n1. \(word)"
        let taskStart = (source as NSString).range(of: "- [ ]").location
        let orderedStart = (source as NSString).range(of: "1. ").location
        var changes: [String] = []
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "LongWords.md"), source: source, epoch: 0),
            rendersMarkdown: true, onSourceChange: { changes.append($0) })
        let fragments = layoutFragments(in: editor.textView)
        guard let bullet = fragments[0] as? NoteBlockLayoutFragment,
            let task = fragments[taskStart] as? NoteBlockLayoutFragment,
            let ordered = fragments[orderedStart] as? NoteBlockLayoutFragment,
            [bullet, task, ordered].allSatisfy({ $0.textLineFragments.count > 1 })
        else { return check("long first words wrap inside their list items", false) }
        check(
            "a long first word leaves the hidden marker on a hairline",
            bullet.textLineFragments[0].typographicBounds.height < 1)
        check(
            "the bullet lines up with the first line of text",
            bullet.firstLine == bullet.textLineFragments[1].typographicBounds)
        let orderedText = ordered.textLineFragments[1]
        check(
            "the number sits on the first line of text's baseline",
            ordered.firstBaseline == orderedText.typographicBounds.minY + orderedText.glyphOrigin.y)

        let text = task.textLineFragments[1].typographicBounds
        let box = NoteCheckboxGeometry.rect(
            level: 0, firstLineHeight: text.height, bodyPointSize: NoteMarkdownTypography.body.pointSize)
        let lowerEdge = CGPoint(x: box.midX, y: task.layoutFragmentFrame.minY + text.minY + box.maxY - 1)
        check(
            "a checkbox under a long first word clicks where it is drawn",
            editor.textView.toggleTask(atContainerPoint: lowerEdge))
        check("clicking it checks that task", changes.last?.contains("- [x] ") == true)
    }

    private static func checkboxCenter(in textView: NSTextView, lineStart: Int) -> CGPoint? {
        guard let fragment = layoutFragments(in: textView)[lineStart] as? NoteBlockLayoutFragment else {
            return nil
        }
        let firstLine = fragment.firstLine
        let box = NoteCheckboxGeometry.rect(
            level: 0, firstLineHeight: firstLine.height, bodyPointSize: NoteMarkdownTypography.body.pointSize)
        return CGPoint(x: box.midX, y: fragment.layoutFragmentFrame.minY + firstLine.minY + box.midY)
    }

    /// Every laid-out fragment, keyed by the source location its paragraph starts at.
    private static func layoutFragments(in textView: NSTextView) -> [Int: NSTextLayoutFragment] {
        guard let layout = textView.textLayoutManager, let content = textView.textContentStorage else {
            return [:]
        }
        var fragments: [Int: NSTextLayoutFragment] = [:]
        layout.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) {
            let location = content.offset(
                from: content.documentRange.location, to: $0.rangeInElement.location)
            fragments[location] = $0
            return true
        }
        return fragments
    }

    private static func font(in textView: NSTextView, at location: Int) -> NSFont? {
        textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    private static func color(in textView: NSTextView, at location: Int) -> NSColor? {
        textView.textStorage?.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    private static func paragraphStyle(in textView: NSTextView, at location: Int) -> NSParagraphStyle? {
        textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil)
            as? NSParagraphStyle
    }

    private static func decoration(in textView: NSTextView, at location: Int) -> NoteBlockDecoration? {
        textView.textStorage?.attribute(.noteBlockDecoration, at: location, effectiveRange: nil)
            as? NoteBlockDecoration
    }

    /// The primitives `copy:`/`cut:`/`paste:` delegate to; the actions clobber the real clipboard.
    private static func copySelection(of textView: NSTextView, to pasteboard: NSPasteboard) {
        let types = textView.writablePasteboardTypes
        pasteboard.declareTypes(types, owner: nil)
        _ = textView.writeSelection(to: pasteboard, types: types)
    }

    private static func cutSelection(of textView: NSTextView, to pasteboard: NSPasteboard) {
        copySelection(of: textView, to: pasteboard)
        textView.delete(nil)
    }

    private static func paste(
        _ text: String, into textView: NSTextView, from pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        _ = textView.readSelection(from: pasteboard)
    }

    private static func makeEditor(
        input: NoteEditorInput,
        rendersMarkdown: Bool = false,
        onSourceChange: @escaping (String) -> Void = { _ in },
        onCountChange: @escaping (NoteEditorInput, Int) -> Void = { _, _ in },
        onFormattingChange: @escaping (NoteEditorInput, NoteFormatting) -> Void = { _, _ in }
    ) -> (coordinator: NoteEditorView.Coordinator, textView: NoteTextView, window: NSWindow) {
        let view = view(
            for: input,
            rendersMarkdown: rendersMarkdown,
            onSourceChange: onSourceChange,
            onCountChange: onCountChange,
            onFormattingChange: onFormattingChange)
        let coordinator = NoteEditorView.Coordinator(parent: view)
        let textView = NoteTextView(usingTextLayoutManager: true)
        NoteEditorView.configure(textView)
        textView.delegate = coordinator
        textView.editorUndoManager = coordinator.editorUndoManager
        textView.setFrameSize(NSSize(width: 320, height: 1))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        scrollView.documentView = textView
        let window = KeyWindow(
            contentRect: scrollView.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.contentView = scrollView
        coordinator.textView = textView
        coordinator.install(input, resetUndo: false)
        window.makeFirstResponder(textView)
        return (coordinator, textView, window)
    }

    private static func view(
        for input: NoteEditorInput,
        rendersMarkdown: Bool = false,
        onSourceChange: @escaping (String) -> Void = { _ in },
        onCountChange: @escaping (NoteEditorInput, Int) -> Void = { _, _ in },
        onFormattingChange: @escaping (NoteEditorInput, NoteFormatting) -> Void = { _, _ in }
    ) -> NoteEditorView {
        NoteEditorView(
            input: input,
            rendersMarkdown: rendersMarkdown,
            onSourceChange: onSourceChange,
            onCharacterCountChange: onCountChange,
            onFormattingChange: onFormattingChange,
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

/// A harness window cannot become key without an active app, and the editor reveals only when key.
private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
