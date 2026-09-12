import Foundation

/// One block of a reply; inline spans stay as source for `AttributedString` in the view.
enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([Item])
    case numberedList(start: Int, items: [Item])
    case code(language: String?, text: String)
    case quote([MarkdownBlock])
    case table(Table)
    case rule

    struct Item: Equatable, Sendable {
        let blocks: [MarkdownBlock]
        /// Set only by a task-list checkbox, so an ordinary bullet keeps its marker.
        let checked: Bool?
    }

    struct Table: Equatable, Sendable {
        enum Alignment: Equatable, Sendable {
            case leading
            case center
            case trailing
        }

        let header: [String]
        let alignments: [Alignment]
        let rows: [[String]]
    }

    /// Tolerates the half-written document a stream produces: an open fence closes at the end.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var reader = MarkdownReader(lines: text.components(separatedBy: "\n"))
        return reader.blocks()
    }
}

private struct MarkdownReader {
    let lines: [String]
    var index = 0

    mutating func blocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        while let line = peek() {
            if line.isBlankLine {
                index += 1
            } else if let fence = MarkdownLine.fence(line) {
                blocks.append(code(fence))
            } else if MarkdownLine.isRule(line) {
                index += 1
                blocks.append(.rule)
            } else if let heading = MarkdownLine.heading(line) {
                index += 1
                blocks.append(heading)
            } else if MarkdownLine.isQuote(line) {
                blocks.append(quote())
            } else if let table = table() {
                blocks.append(table)
            } else if let marker = MarkdownLine.listMarker(line) {
                blocks.append(list(from: marker))
            } else {
                blocks.append(paragraph())
            }
        }
        return blocks
    }

    private func peek(_ offset: Int = 0) -> String? {
        let target = index + offset
        return lines.indices.contains(target) ? lines[target] : nil
    }

    private mutating func code(_ fence: MarkdownLine.Fence) -> MarkdownBlock {
        index += 1
        var body: [String] = []
        while let line = peek(), !MarkdownLine.closes(line, fence) {
            body.append(MarkdownLine.dedent(line, by: fence.indent))
            index += 1
        }
        if peek() != nil { index += 1 }
        while body.last?.isBlankLine == true { body.removeLast() }
        return .code(language: fence.language, text: body.joined(separator: "\n"))
    }

    private mutating func quote() -> MarkdownBlock {
        var inner: [String] = []
        while let line = peek() {
            if MarkdownLine.isQuote(line) {
                inner.append(MarkdownLine.strippingQuoteMarker(line))
            } else if line.isBlankLine || MarkdownLine.startsBlock(line, interrupting: false) {
                break
            } else {
                inner.append(line)
            }
            index += 1
        }
        var reader = MarkdownReader(lines: inner)
        return .quote(reader.blocks())
    }

    private mutating func table() -> MarkdownBlock? {
        guard let header = peek(), header.contains("|"), let delimiter = peek(1),
            let alignments = MarkdownLine.tableAlignments(delimiter)
        else { return nil }
        let titles = MarkdownLine.tableCells(header)
        guard titles.count == alignments.count else { return nil }
        index += 2
        var rows: [[String]] = []
        while let line = peek(), !line.isBlankLine, line.contains("|") {
            rows.append(MarkdownLine.tableCells(line).resized(to: titles.count))
            index += 1
        }
        return .table(.init(header: titles, alignments: alignments, rows: rows))
    }

    private mutating func list(from first: MarkdownLine.Marker) -> MarkdownBlock {
        var items: [MarkdownBlock.Item] = []
        while let line = peek(), let marker = MarkdownLine.listMarker(line),
            marker.isOrdered == first.isOrdered, marker.indent <= first.indent + 1
        {
            index += 1
            items.append(item(startingWith: line, marker: marker))
        }
        guard first.isOrdered else { return .bulletList(items) }
        return .numberedList(start: first.number, items: items)
    }

    private mutating func item(
        startingWith line: String, marker: MarkdownLine.Marker
    )
        -> MarkdownBlock.Item
    {
        var body = [String(line.dropFirst(min(marker.contentIndent, line.count)))]
        while let line = peek() {
            if line.isBlankLine {
                guard let next = peek(1), !next.isBlankLine, next.indent >= marker.contentIndent
                else { break }
            } else if line.indent < marker.contentIndent,
                MarkdownLine.startsBlock(line, interrupting: false)
            {
                break
            }
            body.append(MarkdownLine.dedent(line, by: marker.contentIndent))
            index += 1
        }
        var reader = MarkdownReader(lines: body)
        var blocks = reader.blocks()
        guard case .paragraph(let text) = blocks.first, let task = MarkdownLine.taskBox(text) else {
            return .init(blocks: blocks, checked: nil)
        }
        blocks[0] = .paragraph(task.rest)
        return .init(blocks: blocks, checked: task.checked)
    }

    private mutating func paragraph() -> MarkdownBlock {
        var body: [String] = []
        while let line = peek(), !line.isBlankLine {
            if !body.isEmpty, MarkdownLine.startsBlock(line, interrupting: true) || startsTable() {
                break
            }
            body.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        return .paragraph(body.joined(separator: "\n"))
    }

    private func startsTable() -> Bool {
        guard let header = peek(), header.contains("|"), let delimiter = peek(1) else { return false }
        return MarkdownLine.tableAlignments(delimiter) != nil
    }
}

/// Pure line classification: everything the reader has to recognise before it can consume a block.
private enum MarkdownLine {
    struct Fence {
        let character: Character
        let length: Int
        let indent: Int
        let language: String?
    }

    struct Marker {
        let indent: Int
        /// Column the item's own content starts at, and the amount its later lines are dedented by.
        let contentIndent: Int
        let isOrdered: Bool
        let number: Int
    }

    static func fence(_ line: String) -> Fence? {
        let indent = line.indent
        let body = line.dropFirst(indent)
        guard let character = body.first, character == "`" || character == "~" else { return nil }
        let length = body.prefix(while: { $0 == character }).count
        guard length >= 3 else { return nil }
        let info = body.dropFirst(length).trimmingCharacters(in: .whitespaces)
        guard character == "~" || !info.contains("`") else { return nil }
        let language = info.split(separator: " ").first.map(String.init)
        return Fence(character: character, length: length, indent: indent, language: language)
    }

    static func closes(_ line: String, _ fence: Fence) -> Bool {
        let body = line.dropFirst(line.indent)
        let run = body.prefix(while: { $0 == fence.character }).count
        return run >= fence.length && body.dropFirst(run).allSatisfy(\.isWhitespace)
    }

    static func isRule(_ line: String) -> Bool {
        let body = line.filter { !$0.isWhitespace }
        guard let character = body.first, "-*_".contains(character) else { return false }
        return body.count >= 3 && body.allSatisfy { $0 == character }
    }

    static func heading(_ line: String) -> MarkdownBlock? {
        let body = line.dropFirst(line.indent)
        let level = body.prefix(while: { $0 == "#" }).count
        let rest = body.dropFirst(level)
        guard (1...6).contains(level), rest.isEmpty || rest.first == " " else { return nil }
        return .heading(level: level, text: strippingClosingHashes(rest))
    }

    static func isQuote(_ line: String) -> Bool { line.dropFirst(line.indent).first == ">" }

    static func strippingQuoteMarker(_ line: String) -> String {
        var body = line.dropFirst(line.indent).dropFirst()
        if body.first == " " { body = body.dropFirst() }
        return String(body)
    }

    static func listMarker(_ line: String) -> Marker? {
        let indent = line.indent
        let body = line.dropFirst(indent)
        guard let character = body.first else { return nil }
        var isOrdered = false
        var number = 1
        var width = 1
        if !"-*+".contains(character) {
            let digits = body.prefix(while: \.isNumber)
            guard digits.count <= 9, let value = Int(digits),
                let delimiter = body.dropFirst(digits.count).first, delimiter == "." || delimiter == ")"
            else { return nil }
            isOrdered = true
            number = value
            width = digits.count + 1
        }
        let rest = body.dropFirst(width)
        let gap = rest.prefix(while: { $0 == " " }).count
        guard rest.isEmpty || gap > 0 else { return nil }
        return Marker(
            indent: indent, contentIndent: indent + width + max(gap, 1), isOrdered: isOrdered,
            number: number)
    }

    /// `interrupting` is the CommonMark rule that only a `1.` may cut a paragraph short.
    static func startsBlock(_ line: String, interrupting: Bool) -> Bool {
        if fence(line) != nil || isRule(line) || heading(line) != nil || isQuote(line) { return true }
        guard let marker = listMarker(line) else { return false }
        return !interrupting || (!marker.isOrdered || marker.number == 1)
    }

    static func taskBox(_ text: String) -> (checked: Bool, rest: String)? {
        guard text.count >= 3, text.hasPrefix("["), text.dropFirst(2).first == "]" else { return nil }
        let box = text.dropFirst().first
        guard box == " " || box == "x" || box == "X" else { return nil }
        let rest = text.dropFirst(3)
        guard rest.isEmpty || rest.first == " " else { return nil }
        return (box != " ", String(rest.dropFirst(rest.isEmpty ? 0 : 1)))
    }

    static func tableCells(_ line: String) -> [String] {
        var body = Substring(line.trimmingCharacters(in: .whitespaces))
        if body.first == "|" { body = body.dropFirst() }
        if body.hasSuffix("|"), !body.hasSuffix("\\|") { body = body.dropLast() }
        var cells: [String] = []
        var current = ""
        var isEscaped = false
        for character in body {
            if isEscaped || character == "\\" {
                isEscaped = !isEscaped && character == "\\"
                current.append(character)
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// The pipe is required: without it a lone `---` under a line of prose is a rule, not a table.
    static func tableAlignments(_ line: String) -> [MarkdownBlock.Table.Alignment]? {
        guard line.contains("|") else { return nil }
        var alignments: [MarkdownBlock.Table.Alignment] = []
        for cell in tableCells(line) {
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            let isLeading = cell.hasPrefix(":")
            let isTrailing = cell.hasSuffix(":")
            alignments.append(isLeading && isTrailing ? .center : isTrailing ? .trailing : .leading)
        }
        return alignments.isEmpty ? nil : alignments
    }

    static func dedent(_ line: String, by count: Int) -> String {
        var body = Substring(line)
        var remaining = count
        while remaining > 0, let character = body.first, character == " " || character == "\t" {
            body = body.dropFirst()
            remaining -= 1
        }
        return String(body)
    }

    /// A closing `###` run counts only when spaced off the text, so `# C#` keeps its hash.
    private static func strippingClosingHashes(_ text: Substring) -> String {
        let body = text.trimmingCharacters(in: .whitespaces)
        let hashes = body.reversed().prefix(while: { $0 == "#" }).count
        guard hashes > 0, hashes < body.count,
            body[body.index(body.endIndex, offsetBy: -hashes - 1)] == " "
        else { return body }
        return body.dropLast(hashes).trimmingCharacters(in: .whitespaces)
    }
}

extension StringProtocol {
    fileprivate var isBlankLine: Bool { allSatisfy(\.isWhitespace) }

    /// Leading whitespace measured in characters, so it also indexes back into the line.
    fileprivate var indent: Int { prefix(while: { $0 == " " || $0 == "\t" }).count }
}

extension [String] {
    fileprivate func resized(to count: Int) -> [String] {
        self.count >= count
            ? Array(prefix(count)) : self + Array(repeating: "", count: count - self.count)
    }
}
