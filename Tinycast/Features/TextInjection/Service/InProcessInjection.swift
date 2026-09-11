import AppKit

/// The in-process delivery tier: our own view needs no grant, no pasteboard and no event posting.
extension InjectableTextView {
    /// Where the typed keyword sits — `.pending` until AppKit has handed us the keystroke itself.
    func keywordReplacementState(
        expectedKeyword: String?, keywordLength: Int
    ) -> TextReplacementPolicy.KeywordState {
        let selection = selectedRange()
        guard keywordLength > 0 else { return .matched(selection) }
        guard let expectedKeyword, expectedKeyword.count == keywordLength else { return .rejected }
        return TextReplacementPolicy.keywordState(
            value: string, selectedRange: selection, keyword: expectedKeyword)
    }

    /// Replaces `range` and leaves the caret where the text asks, undoable in the view's own manager.
    @MainActor
    func inject(_ injected: InjectedText, over range: NSRange) {
        // The argument prompt runs modally mid-expansion, so take the caret back before writing.
        if let window, window.firstResponder !== self { window.makeFirstResponder(self) }
        insertText(injected.text, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + injected.caretPrefixLength, length: 0))
        scrollRangeToVisible(selectedRange())
    }
}
