import AppKit
import SwiftUI

@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?
    private var taskButtons: [NSButton] = []
    private var tasks: [NoteTask] = []
    private var codeRanges: [NSRange] = []
    private var needsFullTaskRefresh = false
    private var pendingParagraph: (range: NSRange, delta: Int)?

    override var undoManager: UndoManager? { editorUndoManager }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        pendingParagraph = nil
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        guard !hasMarkedText(), !needsFullTaskRefresh, let replacementString else { return true }
        let source = string as NSString
        let paragraph = source.lineRange(for: affectedCharRange)
        let oldText = source.substring(with: paragraph)
        let localRange = NSRange(location: affectedCharRange.location - paragraph.location,
                                 length: affectedCharRange.length)
        let newText = (oldText as NSString).replacingCharacters(in: localRange, with: replacementString)
        // Fence or line-boundary edits can change the meaning of subsequent paragraphs.
        if replacementString.rangeOfCharacter(from: .newlines) == nil,
            source.substring(with: affectedCharRange).rangeOfCharacter(from: .newlines) == nil,
            !Self.isFence(oldText), !Self.isFence(newText) {
            pendingParagraph = (paragraph, (replacementString as NSString).length - affectedCharRange.length)
        }
        return true
    }

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    func updateTasks() {
        guard !hasMarkedText() else {
            needsFullTaskRefresh = true
            pendingParagraph = nil
            return
        }
        guard let edit = pendingParagraph else {
            refreshTasks()
            return
        }
        pendingParagraph = nil
        let range = NSRange(location: edit.range.location, length: edit.range.length + edit.delta)
        let source = string as NSString
        let inCode = codeRanges.contains { NSLocationInRange(range.location, $0) }
        let replacement = inCode ? [] : NoteTask.parse(source.substring(with: range)).map {
            $0.shifted(by: range.location)
        }
        let start = tasks.firstIndex { $0.markerRange.location >= edit.range.location } ?? tasks.count
        let end = tasks[start...].firstIndex { $0.markerRange.location >= NSMaxRange(edit.range) } ?? tasks.count
        let oldButtons = Array(taskButtons[start..<end])
        var buttons: [NSButton] = []
        for (index, task) in replacement.enumerated() {
            let button = index < oldButtons.count ? oldButtons[index] : makeTaskButton()
            update(button, for: task)
            buttons.append(button)
        }
        oldButtons.dropFirst(replacement.count).forEach { $0.removeFromSuperview() }
        for index in end..<tasks.count { tasks[index] = tasks[index].shifted(by: edit.delta) }
        tasks.replaceSubrange(start..<end, with: replacement)
        taskButtons.replaceSubrange(start..<end, with: buttons)
        for index in start..<taskButtons.count { taskButtons[index].tag = index }
        for index in codeRanges.indices {
            if codeRanges[index].location >= NSMaxRange(edit.range) {
                codeRanges[index].location += edit.delta
            } else if NSLocationInRange(edit.range.location, codeRanges[index]) {
                codeRanges[index].length += edit.delta
            }
        }
        styleTasks(replacement, in: range)
    }

    func refreshTasks() {
        pendingParagraph = nil
        guard !hasMarkedText(), let storage = textStorage else { return }
        needsFullTaskRefresh = false
        (tasks, codeRanges) = NoteTask.scan(string)
        taskButtons.forEach { $0.removeFromSuperview() }
        taskButtons = tasks.enumerated().map { index, task in
            let button = makeTaskButton()
            button.tag = index
            update(button, for: task)
            return button
        }
        styleTasks(tasks, in: NSRange(location: 0, length: storage.length))
    }

    private func makeTaskButton() -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleTask(_:)))
        button.contentTintColor = NSColor(Theme.Colors.noteText)
        button.toolTip = "Toggle Task"
        addSubview(button)
        return button
    }

    private func update(_ button: NSButton, for task: NoteTask) {
        button.state = task.isChecked ? .on : .off
        let label = (string as NSString).substring(with: task.contentRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        button.setAccessibilityLabel(label.isEmpty ? "Task" : label)
    }

    private func styleTasks(_ tasks: [NoteTask], in range: NSRange) {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor(Theme.Colors.noteText), range: range)
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.paragraphStyle, range: range)
        let taskStyle = NSMutableParagraphStyle()
        taskStyle.paragraphSpacing = Theme.Spacing.md
        for task in tasks {
            let paragraph = (string as NSString).lineRange(for: task.markerRange)
            storage.addAttribute(.paragraphStyle, value: taskStyle, range: paragraph)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: task.markerRange)
            if task.isChecked {
                storage.addAttribute(.foregroundColor, value: NSColor(Theme.Colors.textSecondary),
                                     range: task.contentRange)
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                     range: task.contentRange)
            }
        }
        storage.endEditing()
        typingAttributes = NoteEditorView.baseAttributes
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let manager = textLayoutManager, let content = manager.textContentManager else { return }
        for (task, button) in zip(tasks, taskButtons) {
            guard let start = content.location(content.documentRange.location,
                                               offsetBy: task.markerRange.location),
                let end = content.location(start, offsetBy: task.markerRange.length),
                let range = NSTextRange(location: start, end: end) else { continue }
            var markerFrame = CGRect.zero
            manager.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
                markerFrame = frame
                return false
            }
            let size = Theme.Size.noteGlyph
            button.frame = NSRect(x: textContainerOrigin.x + markerFrame.minX,
                                  y: textContainerOrigin.y + markerFrame.midY - size / 2,
                                  width: size, height: size)
            button.isHidden = markerFrame.isEmpty
        }
    }

    @objc private func toggleTask(_ sender: NSButton) {
        guard tasks.indices.contains(sender.tag), !hasMarkedText() else { return }
        let task = tasks[sender.tag]
        let selection = selectedRange()
        breakUndoCoalescing()
        insertText(task.isChecked ? " " : "x", replacementRange: task.stateRange)
        setSelectedRange(selection)
        breakUndoCoalescing()
        window?.makeFirstResponder(self)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let selection = selectedRange()
        if !hasMarkedText(), let text = insertString as? String, text == " ", selection.length == 0,
            replacementRange.location == NSNotFound || replacementRange == selection {
            let source = string as NSString
            let line = source.lineRange(for: selection)
            let prefixRange = NSRange(location: line.location, length: selection.location - line.location)
            let prefix = source.substring(with: prefixRange)
            let trimmed = prefix.trimmingCharacters(in: .whitespaces)
            if trimmed == "[]" || trimmed == "[ ]" {
                let indentation = String(prefix.prefix(while: { $0 == " " || $0 == "\t" }))
                let replacement = indentation + "- [ ] "
                let candidate = source.replacingCharacters(in: prefixRange, with: replacement)
                if NoteTask.parse(candidate).contains(where: {
                    $0.markerRange.location == line.location + (indentation as NSString).length
                }) {
                    super.insertText(replacement, replacementRange: prefixRange)
                    return
                }
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard !hasMarkedText(), selection.length == 0,
            let task = tasks.first(where: {
                selection.location >= $0.contentRange.location
                    && selection.location <= NSMaxRange($0.contentRange)
            }) else {
            super.insertNewline(sender)
            return
        }
        let source = string as NSString
        if source.substring(with: task.contentRange).trimmingCharacters(in: .whitespaces).isEmpty {
            let line = source.lineRange(for: selection)
            insertText("", replacementRange: NSRange(location: line.location,
                                                     length: NSMaxRange(task.contentRange) - line.location))
        } else {
            insertText("\n" + task.continuation, replacementRange: selection)
        }
    }
}
