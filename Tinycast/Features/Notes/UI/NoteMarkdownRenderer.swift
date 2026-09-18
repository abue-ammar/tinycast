import AppKit

/// Keeps a note's parse and reveal state in step with its text view, restyling only what changed.
@MainActor
final class NoteMarkdownRenderer: NSObject, @MainActor NSTextStorageDelegate {
    private(set) var markdown = NoteMarkdown.empty
    private(set) var revealed = IndexSet()
    /// The Render Markdown setting; flipping it takes effect on the next `reset()`.
    var isEnabled: Bool
    weak var textView: NoteTextView? {
        didSet { textView?.textStorage?.delegate = self }
    }

    /// The edit not yet parsed, as the range it covered in `markdown` and the one it covers now.
    private var pendingEdit: (old: NSRange, new: NSRange)?
    private var isStyling = false

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        super.init()
    }

    /// A full parse and restyle, after an install, a setting flip or an appearance change.
    func reset() {
        guard let textView, let storage = textView.textStorage else { return }
        NoteMarkdownStyler.invalidateColors()
        pendingEdit = nil
        guard isEnabled else {
            markdown = .empty
            revealed = []
            restyle(NSRange(location: 0, length: storage.length)) {
                storage.setAttributes(NoteMarkdownStyler.literal, range: $0)
            }
            textView.typingAttributes = NoteMarkdownStyler.literal
            return
        }
        markdown = NoteMarkdownParser.parse(units: Self.units(of: storage))
        revealed = nextRevealed()
        apply(IndexSet(integersIn: markdown.lines.indices))
        textView.typingAttributes = NoteMarkdownStyler.literal
    }

    /// Picks up any edit, however it arrived, then re-hides and reveals lines for the selection.
    func sourceDidChange() {
        syncSource()
        selectionDidChange()
    }

    func selectionDidChange() {
        guard isEnabled, !isStyling, let textView else { return }
        syncSource()
        guard !textView.isDragSelecting else { return }
        let next = nextRevealed()
        let changed = revealed.symmetricDifference(next)
        revealed = next
        if !changed.isEmpty { apply(changed) }
        textView.typingAttributes = NoteMarkdownStyler.literal
    }

    /// The parse of the source as it is right now, for edit plans that must not act on a stale one.
    func syncedMarkdown() -> NoteMarkdown {
        syncSource()
        return markdown
    }

    // MARK: - Edits

    /// Undo and marked text change storage without `textDidChange`, so every callback checks here.
    private func syncSource() {
        guard isEnabled, !isStyling, let edit = pendingEdit, let storage = textView?.textStorage
        else { return }
        pendingEdit = nil
        let old = markdown
        markdown = NoteMarkdownParser.parse(units: Self.units(of: storage))

        let oldLines = old.lineIndexes(intersecting: edit.old)
        let newLines = markdown.lineIndexes(intersecting: edit.new)
        revealed = NoteRevealPolicy.shifted(revealed, editedOldLines: oldLines, editedNewLines: newLines)
        apply(restyleScope(old: old, oldLines: oldLines, newLines: newLines))
    }

    /// The edited lines and one on each side, widened over later lines whose kind or depth changed.
    private func restyleScope(old: NoteMarkdown, oldLines: Range<Int>, newLines: Range<Int>) -> IndexSet {
        let lines = markdown.lines
        guard !lines.isEmpty else { return [] }
        let lower = max(0, newLines.lowerBound - 1)
        let upper = min(lines.count, max(newLines.upperBound, newLines.lowerBound + 1) + 1)
        var scope = IndexSet(integersIn: lower..<upper)
        let delta = newLines.count - oldLines.count

        let shiftedBlocks = old.fenceBlocks.map { block -> ClosedRange<Int> in
            guard block.lowerBound >= oldLines.upperBound else { return block }
            return (block.lowerBound + delta)...(block.upperBound + delta)
        }
        if shiftedBlocks != markdown.fenceBlocks {
            scope.insert(integersIn: lower..<lines.count)
            return scope
        }

        var index = upper
        while index < lines.count {
            let oldIndex = index - delta
            let unchanged =
                old.lines.indices.contains(oldIndex) && old.lines[oldIndex].kind == lines[index].kind
                && old.lines[oldIndex].level == lines[index].level
            if !unchanged {
                scope.insert(index)
            } else if !(lines[index].kind.isList || lines[index].kind == .blank) {
                break
            }
            index += 1
        }
        return scope
    }

    /// Storage reports every mutation here, undo and marked text included; styling never does.
    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing edited: NSTextStorageEditActions,
        range: NSRange, changeInLength delta: Int
    ) {
        guard edited.contains(.editedCharacters) else { return }
        let before = NSRange(location: range.location, length: range.length - delta)
        guard let pending = pendingEdit else {
            pendingEdit = (old: before, new: range)
            return
        }
        let lower = min(pending.old.location, before.location)
        let upper = max(NSMaxRange(pending.new), NSMaxRange(before))
        let shift = pending.new.length - pending.old.length
        pendingEdit = (old: NSRange(lower..<(upper - shift)), new: NSRange(lower..<(upper + delta)))
    }

    private static func units(of storage: NSTextStorage) -> [UInt16] {
        let string = storage.mutableString
        return [UInt16](unsafeUninitializedCapacity: string.length) { buffer, count in
            if let base = buffer.baseAddress {
                string.getCharacters(base, range: NSRange(location: 0, length: string.length))
            }
            count = string.length
        }
    }

    // MARK: - Styling

    private func nextRevealed() -> IndexSet {
        guard let textView else { return [] }
        return NoteRevealPolicy.revealedLines(
            selection: textView.selectedRange(), markdown: markdown, isFocused: textView.isFocused)
    }

    private func apply(_ indexes: IndexSet) {
        guard let textView, let text = textView.textStorage?.mutableString else { return }
        for range in indexes.rangeView where range.lowerBound < markdown.lines.count {
            let lines = range.clamped(to: markdown.lines.indices)
            let span = NSUnionRange(
                markdown.lines[lines.lowerBound].range, markdown.lines[lines.upperBound - 1].range)
            restyle(span) { _ in
                for index in lines {
                    let style = NoteMarkdownStyler.style(
                        at: index, in: markdown, text: text, isRevealed: revealed.contains(index))
                    textView.textStorage?.setAttributes(style.base, range: markdown.lines[index].range)
                    for run in style.runs {
                        textView.textStorage?.addAttributes(run.attributes, range: run.range)
                    }
                }
            }
        }
    }

    /// Attribute writes skip `shouldChangeText`, which is what keeps styling off the undo stack.
    private func restyle(_ range: NSRange, _ write: (NSRange) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        isStyling = true
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            storage.beginEditing()
            write(range)
            storage.endEditing()
        }
        isStyling = false
        invalidateLayout(range)
    }

    /// Without this, a paragraph keeps the fragment it was vended before its decoration changed.
    private func invalidateLayout(_ range: NSRange) {
        guard let textView, let content = textView.textContentStorage,
            let start = content.location(content.documentRange.location, offsetBy: range.location),
            let end = content.location(start, offsetBy: range.length),
            let textRange = NSTextRange(location: start, end: end)
        else { return }
        textView.textLayoutManager?.invalidateLayout(for: textRange)
    }
}
