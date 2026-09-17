import Foundation

/// A Markdown-aware editing gesture the text view asks `NoteMarkdownEditing` to plan.
enum NoteEditAction: Sendable, Equatable {
    enum InlineStyle: Sendable { case bold, italic, strikethrough, code }
    enum ListStyle: Sendable { case bullet, ordered, task }

    case newline
    case deleteBackward
    case indent
    case outdent
    case toggleInline(InlineStyle)
    case toggleLink
    /// Level 0 turns the line back into a plain paragraph.
    case setHeading(level: Int)
    case toggleList(ListStyle)
    case toggleTask(lineIndex: Int)
    /// The `[] ` input rule.
    case typedSpace
    case pasteURL(String)
}
