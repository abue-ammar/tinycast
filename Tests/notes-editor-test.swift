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
        testUndoIsolation()
        testCharacterCountReports()
        testRenderingKeepsSourceAndUndo()
        testHiddenMarkersAndReveal()
        testRestyleFollowsEdits()
        testRenderingOffIsLiteral()
        testTaskSpacing()
        testBlockDecorationsAndFragments()
        testListKeysAndChords()
        testFormattingReports()
        testTaskRuleCheckboxesAndLinks()
        testTasks()
        testTaskEdits()
        print(failures == 0 ? "Notes editor tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
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
        check("the plain editor enables native Find", editor.textView.usesFindPanel)

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
            typing[.font] as? NSFont == NoteMarkdownTypography.body && typing.count == NoteMarkdownStyler.literal.count)

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
        editor.textView.setSelectedRange(NSRange(location: (editor.textView.string as NSString).length, length: 0))
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
            literal = literal && attributes.count == 2
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
                let line = fragment.textLineFragments.first?.typographicBounds ?? .zero
                return NoteCheckboxGeometry.rect(
                    level: 0, firstLineHeight: line.height, bodyPointSize: NoteMarkdownTypography.body.pointSize
                ).offsetBy(dx: 0, dy: fragment.layoutFragmentFrame.minY + line.minY)
            }
            check("task checkboxes have breathing room", box(bottom).minY - box(top).maxY >= Theme.Spacing.md)
        } else {
            check("task checkboxes have breathing room", false)
        }
        for location in [0, second] {
            check("task spacing belongs to its paragraph", style(at: location)?.paragraphSpacing == Theme.Spacing.md)
            check("wrapped task lines retain native spacing", style(at: location)?.lineSpacing == 0)
        }
        let lists = "- one\n- two\n1. three\n2. four"
        editor.coordinator.update(NoteEditorInput(id: NoteID(rawValue: "Lists.md"), source: lists, epoch: 2))
        editor.textView.setSelectedRange(NSRange(location: (lists as NSString).length, length: 0))
        check(
            "bullets and numbered items get the same spacing as tasks",
            [0, 6, 12].allSatisfy { style(at: $0)?.paragraphSpacing == Theme.Spacing.md })
        editor.coordinator.update(NoteEditorInput(id: NoteID(rawValue: "Spacing.md"), source: source, epoch: 3))
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
        let renderedIndent = paragraphStyle(in: editor.textView, at: bullet)?.headIndent
        editor.textView.setSelectedRange(NSRange(location: bullet + 3, length: 0))
        check("a revealed list line carries none", shape("- bullet") == nil)
        let revealed = paragraphStyle(in: editor.textView, at: bullet)
        let markerWidth = ("- " as NSString).size(withAttributes: [.font: NoteMarkdownTypography.body]).width
        check(
            "a revealed list line hangs its marker so the text stays in place",
            revealed?.headIndent == renderedIndent
                && abs((revealed?.firstLineHeadIndent ?? 0) + markerWidth - (renderedIndent ?? 0)) < 0.5)
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
            let firstLine = task.textLineFragments.first?.typographicBounds ?? .zero
            let box = NoteCheckboxGeometry.rect(
                level: 0, firstLineHeight: firstLine.height,
                bodyPointSize: NoteMarkdownTypography.body.pointSize)
            let surface = task.renderingSurfaceBounds.offsetBy(dx: task.layoutFragmentFrame.minX, dy: 0)
            check("the checkbox lies inside the task's drawing surface", surface.contains(box))
        } else {
            check("the checkbox lies inside the task's drawing surface", false)
        }
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
        let claimed = editor.textView.performKeyEquivalent(with: keyDown("b", keyCode: kVK_ANSI_B, in: editor.window))
        check("with rendering off ⌘B is not a formatting chord", !claimed && editor.textView.string == literal)
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
            editor.textView.pasteLink(from: pasteboard) && editor.textView.string == "see [docs](https://a.com)")
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
            indented.count == 2 && indented[1].checkboxRange == NSRange(location: 11, length: 3))
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
        _ characters: String, keyCode: Int, modifiers: NSEvent.ModifierFlags = [.command], in window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)) ?? NSEvent()
    }

    private static func checkboxCenter(in textView: NSTextView, lineStart: Int) -> CGPoint? {
        guard let fragment = layoutFragments(in: textView)[lineStart] as? NoteBlockLayoutFragment else { return nil }
        let firstLine = fragment.textLineFragments.first?.typographicBounds ?? .zero
        let box = NoteCheckboxGeometry.rect(
            level: 0, firstLineHeight: firstLine.height, bodyPointSize: NoteMarkdownTypography.body.pointSize)
        return CGPoint(x: box.midX, y: fragment.layoutFragmentFrame.minY + firstLine.minY + box.midY)
    }

    /// Every laid-out fragment, keyed by the source location its paragraph starts at.
    private static func layoutFragments(in textView: NSTextView) -> [Int: NSTextLayoutFragment] {
        guard let layout = textView.textLayoutManager, let content = textView.textContentStorage else { return [:] }
        var fragments: [Int: NSTextLayoutFragment] = [:]
        layout.enumerateTextLayoutFragments(from: content.documentRange.location, options: [.ensuresLayout]) {
            let location = content.offset(from: content.documentRange.location, to: $0.rangeInElement.location)
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
        textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
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
