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
        testCharacterCountReports()
        testTasks()
        testTaskEdits()
        testTaskSpacing()
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

    private static func testTaskSpacing() {
        let source = "- [ ] first\n- [x] second\nplain\n```\n- [ ] code\n```"
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "Spacing.md"), source: source, epoch: 1))
        editor.textView.layoutSubtreeIfNeeded()
        let buttons = editor.textView.subviews.compactMap { $0 as? NSButton }
        check(
            "task checkboxes have breathing room",
            buttons.count == 2 && buttons[1].frame.minY - buttons[0].frame.maxY >= Theme.Spacing.md)
        for task in NoteTask.parse(source) {
            let style =
                editor.textView.textStorage?.attribute(
                    .paragraphStyle, at: task.markerRange.location, effectiveRange: nil) as? NSParagraphStyle
            check("task spacing belongs to its paragraph", style?.paragraphSpacing == Theme.Spacing.md)
            check("wrapped task lines retain native spacing", style?.lineSpacing == 0)
        }
        for text in ["plain", "- [ ] code"] {
            let location = (source as NSString).range(of: text).location
            check(
                "non-task paragraphs retain native spacing",
                editor.textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil)
                    == nil)
        }
        editor.textView.setSelectedRange(NSRange(location: 0, length: 6))
        editor.textView.insertText("", replacementRange: editor.textView.selectedRange())
        check(
            "removing a task marker removes its spacing",
            editor.textView.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) == nil)
        editor.coordinator.editorUndoManager.undo()
        check("undo restores task source without adding blank lines", editor.textView.string == source)
    }

    private static func testTaskEdits() {
        let source = "- [ ] first\n- [ ]    \n```\n- [ ] literal\n```\n- [x] last"
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "Edits.md"), source: source, epoch: 1))
        let original = editor.textView.subviews.compactMap { $0 as? NSButton }
        check("blank tasks have meaningful labels", original[1].accessibilityLabel() == "Task")
        editor.textView.setSelectedRange(NSRange(location: 11, length: 0))
        editor.textView.insertText(" longer", replacementRange: editor.textView.selectedRange())
        let updated = editor.textView.subviews.compactMap { $0 as? NSButton }
        check(
            "typing preserves task controls",
            original.count == updated.count && zip(original, updated).allSatisfy { $0 === $1 })
        check("typing updates the accessible name", updated[0].accessibilityLabel() == "first longer")
        updated[2].performClick(nil)
        check("later tasks retain correct toggle offsets", editor.textView.string.hasSuffix("- [ ] last"))
        let literal = (editor.textView.string as NSString).range(of: "literal")
        editor.textView.insertText("code", replacementRange: literal)
        check(
            "editing fenced text keeps it literal",
            editor.textView.subviews.compactMap { $0 as? NSButton }.count == 3)
        editor.coordinator.editorUndoManager.undo()
        check("undo preserves fenced text", editor.textView.string.contains("literal"))
        editor.textView.insertText("", replacementRange: NSRange(location: 0, length: 6))
        check(
            "removing a marker removes only its control",
            editor.textView.subviews.compactMap { $0 as? NSButton }.count == 2)
        editor.textView.insertText("- [ ] ", replacementRange: NSRange(location: 0, length: 0))
        check(
            "restoring a marker restores its control",
            editor.textView.subviews.compactMap { $0 as? NSButton }.count == 3)
        let fence = (editor.textView.string as NSString).range(of: "```")
        editor.textView.insertText("plain", replacementRange: fence)
        check(
            "changing a fence reparses subsequent tasks",
            NoteTask.parse(editor.textView.string).count
                == editor.textView.subviews.compactMap { $0 as? NSButton }.count)
        editor.coordinator.editorUndoManager.undo()
        check(
            "undoing a fence restores subsequent tasks",
            NoteTask.parse(editor.textView.string).count
                == editor.textView.subviews.compactMap { $0 as? NSButton }.count)
        editor.textView.selectAll(nil)
        editor.textView.insertText("```\n", replacementRange: editor.textView.selectedRange())
        editor.textView.insertText("- [ ] hidden", replacementRange: editor.textView.selectedRange())
        check(
            "typing at the end of an open fence stays literal",
            editor.textView.subviews.compactMap { $0 as? NSButton }.isEmpty)
    }

    private static func testTasks() {
        let source = "- [ ] 🧑🏽‍💻 first\n* [X] done\n```md\n- [ ] code\n```\n~~~\n- [x] code\n~~~"
        let parsed = NoteTask.parse(source)
        check("fenced tasks remain literal", parsed.count == 2)
        check("uppercase X is checked", parsed.last?.isChecked == true)
        check(
            "inline syntax and incomplete markers stay literal",
            NoteTask.parse("inline - [ ] task\n- [] task\n- [q] task").isEmpty)
        let indented = NoteTask.parse("hello\r\n  + [ ] task\r\n")
        check(
            "indented CRLF tasks preserve offsets and indentation",
            indented.first?.markerRange.location == 9 && indented.first?.continuation == "  - [ ] ")
        check(
            "task content ranges preserve Unicode",
            (source as NSString).substring(with: parsed[0].contentRange) == "🧑🏽‍💻 first")
        var changes: [String] = []
        let editor = makeEditor(
            input: NoteEditorInput(id: NoteID(rawValue: "Tasks.md"), source: source, epoch: 1),
            onSourceChange: { changes.append($0) })
        editor.textView.layoutSubtreeIfNeeded()
        let buttons = editor.textView.subviews.compactMap { $0 as? NSButton }
        check("tasks have accessible checkbox controls", buttons.count == 2)
        check("task controls have layout", buttons.allSatisfy { !$0.isHidden && $0.frame.height > 0 })
        check("rendering does not rewrite source", editor.textView.string == source)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        editor.textView.selectAll(nil)
        copySelection(of: editor.textView, to: pasteboard)
        check("copying tasks preserves Markdown", pasteboard.string(forType: .string) == source)
        editor.textView.setSelectedRange(NSRange(location: NSMaxRange(parsed[0].contentRange), length: 0))
        buttons[0].performClick(nil)
        check("clicking saves checked Markdown", changes.last?.hasPrefix("- [x] ") == true)
        check(
            "clicking preserves the caret",
            editor.textView.selectedRange().location == NSMaxRange(parsed[0].contentRange))
        editor.coordinator.editorUndoManager.undo()
        check("checkbox toggle is undoable", editor.textView.string == source)
        editor.coordinator.editorUndoManager.redo()
        check("checkbox toggle is redoable", editor.textView.string.hasPrefix("- [x] "))
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
            editor.textView.textStorage?.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
                == NSColor(Theme.Colors.noteText))
        editor.textView.selectAll(nil)
        editor.textView.insertText("```\n[]", replacementRange: editor.textView.selectedRange())
        editor.textView.insertText(" ", replacementRange: editor.textView.selectedRange())
        check("bracket shortcuts stay literal in code", editor.textView.string == "```\n[] ")
        let replacement = NoteEditorInput(id: NoteID(rawValue: "Other.md"), source: "plain", epoch: 2)
        editor.coordinator.update(replacement)
        check(
            "switching notes removes old checkboxes",
            editor.textView.subviews.compactMap { $0 as? NSButton }.isEmpty)
        check("switching notes clears task undo", !editor.coordinator.editorUndoManager.canUndo)
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
        onSourceChange: @escaping (String) -> Void = { _ in },
        onCountChange: @escaping (NoteEditorInput, Int) -> Void = { _, _ in }
    ) -> (coordinator: NoteEditorView.Coordinator, textView: NoteTextView, window: NSWindow) {
        let view = view(
            for: input,
            onSourceChange: onSourceChange,
            onCountChange: onCountChange)
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
        window.makeFirstResponder(textView)
        return (coordinator, textView, window)
    }

    private static func view(
        for input: NoteEditorInput,
        onSourceChange: @escaping (String) -> Void = { _ in },
        onCountChange: @escaping (NoteEditorInput, Int) -> Void = { _, _ in }
    ) -> NoteEditorView {
        NoteEditorView(
            input: input,
            onSourceChange: onSourceChange,
            onCharacterCountChange: onCountChange,
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
