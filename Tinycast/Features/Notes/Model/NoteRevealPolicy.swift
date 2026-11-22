import Foundation

/// Decides which lines show their raw Markdown rather than its rendered form.
enum NoteRevealPolicy {
    /// Lines that show raw syntax: those under the selection, widened to whole fenced blocks.
    static func revealedLines(
        selection: NSRange, markdown: NoteMarkdown, isFocused: Bool
    ) -> IndexSet {
        guard isFocused, selection.location != NSNotFound else { return IndexSet() }
        var revealed = IndexSet(integersIn: markdown.lineIndexes(intersecting: selection))
        guard let first = revealed.first, let last = revealed.last else { return revealed }
        for block in markdown.fenceBlocks where block.overlaps(first...last) {
            revealed.insert(block.lowerBound)
            revealed.insert(block.upperBound)
        }
        return revealed
    }

    /// Bullets keep their dot under the caret, so their marker stays hidden on a revealed line too.
    static func hidesMarker(of line: NoteMarkdown.Line, isRevealed: Bool) -> Bool {
        line.markerRange != nil && (!isRevealed || line.kind == .bullet)
    }

    /// Never inside syntax its line hides: every spot there looks the same, and typing splits it.
    static func restingCaret(
        _ proposed: Int, from previous: Int, steppingByCharacter: Bool, markdown: NoteMarkdown,
        revealed: IndexSet
    ) -> Int {
        guard let index = markdown.lineIndex(at: proposed) else { return proposed }
        let line = markdown.lines[index]
        let isRevealed = revealed.contains(index)
        if let marker = line.markerRange, marker.location..<line.contentRange.location ~= proposed,
            hidesMarker(of: line, isRevealed: isRevealed)
        {
            let contentStart = line.contentRange.location
            // Only a character step off the content start crosses back; a repeat click there stays put.
            guard steppingByCharacter, previous == contentStart, index > 0 else { return contentStart }
            return NSMaxRange(markdown.lines[index - 1].contentRange)
        }
        guard !isRevealed else { return proposed }
        return caret(leavingDelimitersOf: markdown.inlines(of: line), at: proposed)
    }

    private static func caret(
        leavingDelimitersOf inlines: [NoteMarkdown.Inline], at proposed: Int
    ) -> Int {
        for inline in inlines {
            for marker in inline.markerRanges
            where marker.location < proposed && proposed < NSMaxRange(marker) {
                return marker.location < inline.contentRange.location ? NSMaxRange(marker) : marker.location
            }
        }
        return proposed
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
}
