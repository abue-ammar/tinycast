import Foundation

/// Which lines show raw Markdown: those under the selection, and only while the editor has focus.
enum NoteRevealPolicy {
    /// Lines that show raw syntax: those under the selection, widened to whole fenced blocks.
    static func revealedLines(
        selection: NSRange, markdown: NoteMarkdown, isFocused: Bool
    ) -> IndexSet {
        guard isFocused, selection.location != NSNotFound, !isAfterFinalTerminator(selection, markdown)
        else { return IndexSet() }
        var revealed = IndexSet(integersIn: markdown.lineIndexes(intersecting: selection))
        guard let first = revealed.first, let last = revealed.last else { return revealed }
        for block in markdown.fenceBlocks where block.overlaps(first...last) {
            revealed.insert(block.lowerBound)
            revealed.insert(block.upperBound)
        }
        return revealed
    }

    /// Carries a revealed set across an edit so stale lines can still be found and re-hidden.
    static func shifted(
        _ revealed: IndexSet, editedOldLines: Range<Int>, editedNewLines: Range<Int>
    ) -> IndexSet {
        let delta = editedNewLines.count - editedOldLines.count
        var shifted = IndexSet()
        for index in revealed where !editedOldLines.contains(index) {
            shifted.insert(index < editedOldLines.lowerBound ? index : index + delta)
        }
        shifted.insert(integersIn: editedNewLines)
        return shifted
    }

    /// A caret on the empty row after a final newline sits on no line at all.
    private static func isAfterFinalTerminator(_ selection: NSRange, _ markdown: NoteMarkdown) -> Bool {
        guard selection.length == 0, let last = markdown.lines.last else { return false }
        return selection.location == NSMaxRange(last.range)
            && NSMaxRange(last.contentRange) < NSMaxRange(last.range)
    }
}
