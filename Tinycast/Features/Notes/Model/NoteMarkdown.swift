import Foundation

/// A note's Markdown as ranged lines; one line is one TextKit paragraph and one restyle unit.
struct NoteMarkdown: Sendable, Equatable {
    struct Line: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case blank
            case paragraph
            case heading(level: Int)
            case bullet
            case ordered(number: Int)
            case task(checked: Bool)
            case quote(depth: Int)
            case rule
            case fenceOpen(language: String?)
            case fenceClose
            case code
            /// A row of a GFM table, which stays literal: no inline spans, no block syntax.
            case table

            var isList: Bool {
                switch self {
                case .bullet, .ordered, .task: true
                default: false
                }
            }

            var isFenced: Bool {
                switch self {
                case .fenceOpen, .fenceClose, .code: true
                default: false
                }
            }
        }

        let kind: Kind
        /// The whole line including its terminator, so ranges tile the source with no gaps.
        let range: NSRange
        /// The line without leading block syntax and without its terminator.
        let contentRange: NSRange
        /// Leading indentation plus block marker plus the space after it; nil when there is none.
        let markerRange: NSRange?
        /// The three characters `[ ]` or `[x]` of a task; nil otherwise.
        let checkboxRange: NSRange?
        /// List nesting depth from the indent stack, 0 for top level and for non-list lines.
        let level: Int
    }

    struct Inline: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case strong, emphasis, strongEmphasis, strikethrough, code
            case link(destination: String)
            case autolink
        }

        let kind: Kind
        let range: NSRange
        let contentRange: NSRange
        /// Every syntax run to hide: opening and closing delimiters, and `](url)` for a link.
        let markerRanges: [NSRange]
    }

    /// The source the lines were parsed from; line shapes alone do not identify a note.
    let units: [UInt16]
    let lines: [Line]
    /// Line index ranges of fenced blocks, open line through close line (or last line if unclosed).
    let fenceBlocks: [ClosedRange<Int>]

    static let empty = NoteMarkdown(units: [], lines: [], fenceBlocks: [])

    /// Scanned on demand: every consumer wants one line, and storing all of them costs more.
    func inlines(of line: Line) -> [Inline] {
        switch line.kind {
        case .paragraph, .heading, .quote, .bullet, .ordered, .task:
            NoteInlineScanner(units: units)
                .inlines(in: line.contentRange.location..<NSMaxRange(line.contentRange))
        default:
            []
        }
    }

    /// Binary search; the parser's trailing empty line is what a caret at the very end lands on.
    func lineIndex(at location: Int) -> Int? {
        guard let last = lines.last, 0...NSMaxRange(last.range) ~= location else { return nil }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].range.location <= location {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// An empty range touches its own line; a range ending at a line start does not reach it.
    func lineIndexes(intersecting range: NSRange) -> Range<Int> {
        guard let first = lineIndex(at: range.location) else { return 0..<0 }
        guard range.length > 0, let last = lineIndex(at: NSMaxRange(range) - 1) else {
            return first..<(first + 1)
        }
        return first..<(max(first, last) + 1)
    }
}
