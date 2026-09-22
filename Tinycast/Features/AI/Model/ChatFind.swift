import Foundation

/// One match of find: the message, the drawn text it sits in, and which match within that text.
struct ChatFindOccurrence: Equatable, Hashable, Sendable {
    let messageID: UUID
    /// Where the drawn text sits, not what it says: two identical table cells are two places.
    let leaf: [Int]
    let index: Int
}

/// Every match in a transcript in reading order, walked exactly as the transcript draws it.
enum ChatFindIndex {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func occurrences(of query: String, in messages: [ChatMessage]) -> [ChatFindOccurrence] {
        guard !query.isEmpty else { return [] }
        return messages.flatMap { message in
            leaves(of: message).flatMap { leaf in
                ranges(of: query, in: leaf.visible).indices.map {
                    ChatFindOccurrence(messageID: message.id, leaf: leaf.path, index: $0)
                }
            }
        }
    }

    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var from = text.startIndex
        while let range = text.range(of: query, options: options, range: from..<text.endIndex) {
            found.append(range)
            from = range.upperBound
        }
        return found
    }

    typealias Leaf = (path: [Int], visible: String)

    /// Each text a message draws, in order, by the same path the transcript's views build.
    static func leaves(of message: ChatMessage) -> [Leaf] {
        guard message.role == .assistant else { return [([0], message.text)] }
        return message.segments.enumerated().flatMap { offset, segment -> [Leaf] in
            switch segment {
            case .text(let text):
                return leaves(of: MarkdownBlock.parse(ChatChoices.split(text).text), at: [offset])
            case .reasoning(let block): return [([offset], block.text)]
            case .search, .tools: return []
            }
        }
    }

    private static func leaves(of blocks: [MarkdownBlock], at prefix: [Int]) -> [Leaf] {
        blocks.enumerated().flatMap { offset, block -> [Leaf] in
            let path = prefix + [offset]
            switch block {
            case .heading(_, let text), .paragraph(let text): return [(path, inline(text))]
            case .bulletList(let items), .numberedList(_, let items):
                return items.enumerated().flatMap { leaves(of: $1.blocks, at: path + [$0]) }
            case .code(_, let text): return [(path, text)]
            case .quote(let blocks): return leaves(of: blocks, at: path)
            case .table(let table):
                return ([table.header] + table.rows).enumerated().flatMap { row, cells in
                    cells.enumerated().map { (path + [row, $0], inline($1)) }
                }
            case .rule: return []
            }
        }
    }

    private static func inline(_ source: String) -> String {
        String(MarkdownBlock.inline(source).characters)
    }
}
