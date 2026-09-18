import Foundation

/// The formatting a selection already carries; each flag means that toggle would remove it.
struct NoteFormatting: Sendable, Equatable {
    /// 1 to 6 when every heading-able line is that heading, 0 when every one is a paragraph.
    var headingLevel: Int?
    var inlineStyles: Set<NoteEditAction.InlineStyle>
    var isLink: Bool
    var isCodeBlock: Bool
    var isQuote: Bool
    var list: NoteEditAction.ListStyle?

    static let plain = NoteFormatting(
        headingLevel: nil, inlineStyles: [], isLink: false, isCodeBlock: false, isQuote: false, list: nil)
}
