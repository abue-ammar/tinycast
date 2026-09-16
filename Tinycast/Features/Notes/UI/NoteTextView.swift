import AppKit
import SwiftUI

@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?
    private var taskButtons: [NSButton] = []
    private var tasks: [NoteTask] = []

    override var undoManager: UndoManager? { editorUndoManager }

    func refreshTasks() {
        guard !hasMarkedText(), let storage = textStorage else { return }
        tasks = NoteTask.parse(string)
        let range = NSRange(location: 0, length: storage.length)
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
        taskButtons.forEach { $0.removeFromSuperview() }
        taskButtons = tasks.enumerated().map { index, task in
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleTask(_:)))
            button.tag = index
            button.state = task.isChecked ? .on : .off
            button.contentTintColor = NSColor(Theme.Colors.noteText)
            let label = (string as NSString).substring(with: task.contentRange)
            button.setAccessibilityLabel(label.isEmpty ? "Task" : label)
            button.toolTip = "Toggle Task"
            addSubview(button)
            return button
        }
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
