import AppKit

/// Vends a drawing fragment for every paragraph whose first character carries a block decoration.
final class NoteLayoutFragmentProvider: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let paragraph = (textElement as? NSTextParagraph)?.attributedString
        guard let paragraph, paragraph.length > 0,
            let decoration = paragraph.attribute(.noteBlockDecoration, at: 0, effectiveRange: nil)
                as? NoteBlockDecoration
        else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        return NoteBlockLayoutFragment(
            textElement: textElement, range: textElement.elementRange, decoration: decoration)
    }
}
