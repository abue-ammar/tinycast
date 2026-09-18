import Foundation

/// Parses a note's source into ranged lines: the GFM subset Notes renders, everything else literal.
enum NoteMarkdownParser {
    static func parse(_ source: String) -> NoteMarkdown {
        parse(units: Array(source.utf16))
    }

    static func parse(units: [UInt16]) -> NoteMarkdown {
        var lines: [NoteMarkdown.Line] = []
        var indents: [Int] = []
        var fenceBlocks: [ClosedRange<Int>] = []
        var fence: Fence?
        var start = 0
        while start < units.count {
            let (contentEnd, end) = lineBounds(units, from: start)
            let scan = LineScan(units: units, start: start, end: contentEnd)
            if let open = fence {
                if scan.closes(open) {
                    lines.append(scan.wholeLine(.fenceClose, range: start..<end))
                    fenceBlocks.append(open.lineIndex...lines.count - 1)
                    fence = nil
                } else {
                    lines.append(scan.code(range: start..<end))
                }
                indents.append(0)
            } else if let opened = scan.opensFence(lineIndex: lines.count) {
                fence = opened
                lines.append(scan.wholeLine(.fenceOpen(language: opened.language), range: start..<end))
                indents.append(0)
            } else {
                lines.append(scan.block(range: start..<end))
                indents.append(scan.indentColumns)
            }
            start = end
        }
        if let open = fence {
            fenceBlocks.append(open.lineIndex...lines.count - 1)
        }
        // A caret after the final terminator has to land on a line, so the empty row is a real one.
        if lines.last.map({ NSMaxRange($0.contentRange) < NSMaxRange($0.range) }) ?? true {
            let end = NSRange(location: units.count, length: 0)
            lines.append(
                NoteMarkdown.Line(
                    kind: .blank, range: end, contentRange: end, markerRange: nil, checkboxRange: nil,
                    level: 0))
            indents.append(0)
        }
        return NoteMarkdown(
            units: units, lines: leveled(tabled(lines, units: units), indents: indents),
            fenceBlocks: fenceBlocks)
    }

    fileprivate struct Fence {
        let marker: UInt16
        let length: Int
        let language: String?
        let lineIndex: Int
    }

    private static let maximumLevel = 6

    /// The ASCII code units the grammar is written in; every delimiter is one UTF-16 unit.
    enum Unit {
        static let tab: UInt16 = 0x09
        static let newline: UInt16 = 0x0A
        static let carriageReturn: UInt16 = 0x0D
        static let space: UInt16 = 0x20
        static let exclamation: UInt16 = 0x21
        static let hash: UInt16 = 0x23
        static let openParen: UInt16 = 0x28
        static let closeParen: UInt16 = 0x29
        static let asterisk: UInt16 = 0x2A
        static let plus: UInt16 = 0x2B
        static let dash: UInt16 = 0x2D
        static let period: UInt16 = 0x2E
        static let zero: UInt16 = 0x30
        static let nine: UInt16 = 0x39
        static let colon: UInt16 = 0x3A
        static let greaterThan: UInt16 = 0x3E
        static let upperX: UInt16 = 0x58
        static let openBracket: UInt16 = 0x5B
        static let backslash: UInt16 = 0x5C
        static let closeBracket: UInt16 = 0x5D
        static let underscore: UInt16 = 0x5F
        static let backtick: UInt16 = 0x60
        static let lowerX: UInt16 = 0x78
        static let pipe: UInt16 = 0x7C
        static let tilde: UInt16 = 0x7E

        static func isSpaceOrTab(_ unit: UInt16) -> Bool { unit == space || unit == tab }
        static func isDigit(_ unit: UInt16) -> Bool { (zero...nine).contains(unit) }

        static func isASCIIPunctuation(_ unit: UInt16) -> Bool {
            (0x21...0x2F).contains(unit) || (0x3A...0x40).contains(unit)
                || (0x5B...0x60).contains(unit) || (0x7B...0x7E).contains(unit)
        }

        /// Surrogates count as not alphanumeric; every delimiter test only needs the ASCII answer.
        static func isAlphanumeric(_ unit: UInt16) -> Bool {
            guard let scalar = Unicode.Scalar(unit) else { return false }
            return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
        }

        static func isWhitespace(_ unit: UInt16) -> Bool {
            guard let scalar = Unicode.Scalar(unit) else { return false }
            return scalar.properties.isWhitespace
        }
    }

    /// Matches `NSString.lineRange(for:)`, so a line is exactly one TextKit paragraph.
    private static func lineBounds(_ units: [UInt16], from start: Int) -> (contentEnd: Int, end: Int) {
        var index = start
        while index < units.count {
            switch units[index] {
            case Unit.newline, 0x85, 0x2028, 0x2029:
                return (index, index + 1)
            case Unit.carriageReturn:
                let crlf = index + 1 < units.count && units[index + 1] == Unit.newline
                return (index, index + (crlf ? 2 : 1))
            default:
                index += 1
            }
        }
        return (index, index)
    }

    /// A header row, a delimiter row with as many cells, then every following row with a pipe.
    private static func tabled(_ lines: [NoteMarkdown.Line], units: [UInt16]) -> [NoteMarkdown.Line] {
        var result = lines
        var index = 0
        while index + 1 < lines.count {
            guard lines[index].kind == .paragraph, lines[index + 1].kind == .paragraph,
                let header = tableCells(of: lines[index], in: units),
                let delimiter = tableCells(of: lines[index + 1], in: units),
                delimiter.count == header.count, delimiter.allSatisfy(isDelimiterCell)
            else {
                index += 1
                continue
            }
            var end = index + 2
            while end < lines.count, lines[end].kind == .paragraph,
                tableCells(of: lines[end], in: units) != nil {
                end += 1
            }
            for row in index..<end {
                let line = lines[row]
                result[row] = NoteMarkdown.Line(
                    kind: .table, range: line.range, contentRange: line.contentRange, markerRange: nil,
                    checkboxRange: nil, level: 0)
            }
            index = end
        }
        return result
    }

    /// A row's cells split on unescaped pipes, outer pipes dropped; nil for a line with no pipe.
    private static func tableCells(of line: NoteMarkdown.Line, in units: [UInt16]) -> [ArraySlice<UInt16>]? {
        let content = units[line.contentRange.location..<NSMaxRange(line.contentRange)]
        var row = content.drop(while: Unit.isSpaceOrTab)
        while let last = row.last, Unit.isSpaceOrTab(last) { row = row.dropLast() }
        var cells: [ArraySlice<UInt16>] = []
        var cellStart = row.startIndex
        var sawPipe = false
        var index = row.startIndex
        while index < row.endIndex {
            if row[index] == Unit.backslash {
                index += 2
                continue
            }
            if row[index] == Unit.pipe {
                sawPipe = true
                cells.append(row[cellStart..<index])
                cellStart = index + 1
            }
            index += 1
        }
        guard sawPipe else { return nil }
        cells.append(row[min(cellStart, row.endIndex)..<row.endIndex])
        if row.first == Unit.pipe { cells.removeFirst() }
        if row.last == Unit.pipe, row.count > 1 { cells.removeLast() }
        return cells
    }

    private static func isDelimiterCell(_ cell: ArraySlice<UInt16>) -> Bool {
        var dashes = cell.drop(while: Unit.isSpaceOrTab)
        while let last = dashes.last, Unit.isSpaceOrTab(last) { dashes = dashes.dropLast() }
        if dashes.first == Unit.colon { dashes = dashes.dropFirst() }
        if dashes.last == Unit.colon { dashes = dashes.dropLast() }
        return !dashes.isEmpty && dashes.allSatisfy { $0 == Unit.dash }
    }

    /// Assigns list depth with an indent stack, so two-space, four-space and tab nesting all work.
    private static func leveled(_ lines: [NoteMarkdown.Line], indents: [Int]) -> [NoteMarkdown.Line] {
        var stack: [Int] = []
        return lines.enumerated().map { index, line in
            switch line.kind {
            case .blank:
                return line
            case .bullet, .ordered, .task:
                let indent = indents[index]
                while let top = stack.last, top > indent { stack.removeLast() }
                if stack.last.map({ $0 < indent }) ?? true { stack.append(indent) }
                let level = min(stack.count - 1, maximumLevel)
                guard level != line.level else { return line }
                return NoteMarkdown.Line(
                    kind: line.kind, range: line.range, contentRange: line.contentRange,
                    markerRange: line.markerRange, checkboxRange: line.checkboxRange, level: level)
            default:
                stack.removeAll()
                return line
            }
        }
    }

    // MARK: - Blocks

    fileprivate struct LineScan {
        let units: [UInt16]
        let start: Int
        let end: Int

        /// Where indentation ends and how many columns it spans, a tab counting as four.
        var indentEnd: Int { indentation.end }
        var indentColumns: Int { indentation.columns }

        private var indentation: (end: Int, columns: Int) {
            var index = start
            var columns = 0
            while index < end, Unit.isSpaceOrTab(units[index]) {
                columns += units[index] == Unit.tab ? 4 : 1
                index += 1
            }
            return (index, columns)
        }

        func wholeLine(_ kind: NoteMarkdown.Line.Kind, range: Range<Int>) -> NoteMarkdown.Line {
            NoteMarkdown.Line(
                kind: kind, range: NSRange(range), contentRange: NSRange(location: end, length: 0),
                markerRange: NSRange(start..<end), checkboxRange: nil, level: 0)
        }

        func code(range: Range<Int>) -> NoteMarkdown.Line {
            NoteMarkdown.Line(
                kind: .code, range: NSRange(range), contentRange: NSRange(start..<end),
                markerRange: nil, checkboxRange: nil, level: 0)
        }

        func closes(_ fence: Fence) -> Bool {
            guard indentColumns <= 3 else { return false }
            let runEnd = run(of: fence.marker, from: indentEnd)
            guard runEnd - indentEnd >= fence.length else { return false }
            return units[runEnd..<end].allSatisfy(Unit.isSpaceOrTab)
        }

        func opensFence(lineIndex: Int) -> Fence? {
            guard indentColumns <= 3, indentEnd < end else { return nil }
            let marker = units[indentEnd]
            guard marker == Unit.backtick || marker == Unit.tilde else { return nil }
            let runEnd = run(of: marker, from: indentEnd)
            guard runEnd - indentEnd >= 3 else { return nil }
            let info = units[runEnd..<end]
            if marker == Unit.backtick, info.contains(Unit.backtick) { return nil }
            let word = info.drop(while: Unit.isSpaceOrTab).prefix { !Unit.isSpaceOrTab($0) }
            let language = word.isEmpty ? nil : String(decoding: word, as: UTF16.self)
            return Fence(
                marker: marker, length: runEnd - indentEnd, language: language, lineIndex: lineIndex)
        }

        func block(range: Range<Int>) -> NoteMarkdown.Line {
            let lineRange = NSRange(range)
            if units[start..<end].allSatisfy(Unit.isSpaceOrTab) {
                return plain(.blank, range: lineRange, contentStart: start)
            }
            if indentColumns <= 3, isRule {
                return wholeLine(.rule, range: range)
            }
            let first = indentEnd
            if indentColumns <= 3, let line = heading(range: lineRange, from: first) { return line }
            if indentColumns <= 3, let line = quote(range: lineRange, from: first) { return line }
            if let line = listItem(range: lineRange, from: first) { return line }
            return plain(.paragraph, range: lineRange, contentStart: start)
        }

        private var isRule: Bool {
            let marks = units[start..<end].filter { !Unit.isSpaceOrTab($0) }
            guard marks.count >= 3, let mark = marks.first else { return false }
            guard mark == Unit.dash || mark == Unit.asterisk || mark == Unit.underscore else {
                return false
            }
            return marks.allSatisfy { $0 == mark }
        }

        private func heading(range: NSRange, from first: Int) -> NoteMarkdown.Line? {
            let hashesEnd = run(of: Unit.hash, from: first)
            let level = hashesEnd - first
            guard (1...6).contains(level) else { return nil }
            guard let markerEnd = separated(after: hashesEnd) else { return nil }
            return marked(.heading(level: level), range: range, markerEnd: markerEnd)
        }

        private func quote(range: NSRange, from first: Int) -> NoteMarkdown.Line? {
            var index = first
            var depth = 0
            while index < end, units[index] == Unit.greaterThan {
                depth += 1
                index += 1
                if index < end, units[index] == Unit.space { index += 1 }
            }
            guard depth > 0 else { return nil }
            return marked(.quote(depth: depth), range: range, markerEnd: index)
        }

        private func listItem(range: NSRange, from first: Int) -> NoteMarkdown.Line? {
            guard first < end else { return nil }
            let unit = units[first]
            if unit == Unit.dash || unit == Unit.asterisk || unit == Unit.plus {
                guard let markerEnd = separated(after: first + 1) else { return nil }
                if let task = task(range: range, bulletEnd: first + 1, markerEnd: markerEnd) {
                    return task
                }
                return marked(.bullet, range: range, markerEnd: markerEnd)
            }
            let digitsEnd = units[first..<end].firstIndex { !Unit.isDigit($0) } ?? end
            let digits = digitsEnd - first
            guard (1...9).contains(digits), digitsEnd < end else { return nil }
            guard units[digitsEnd] == Unit.period || units[digitsEnd] == Unit.closeParen else {
                return nil
            }
            guard let markerEnd = separated(after: digitsEnd + 1) else { return nil }
            let number = units[first..<digitsEnd].reduce(0) { $0 * 10 + Int($1 - Unit.zero) }
            return marked(.ordered(number: number), range: range, markerEnd: markerEnd)
        }

        private func task(range: NSRange, bulletEnd: Int, markerEnd: Int) -> NoteMarkdown.Line? {
            let open = bulletEnd + 1
            guard markerEnd == open, open + 2 < end, units[open] == Unit.openBracket,
                units[open + 2] == Unit.closeBracket
            else { return nil }
            let mark = units[open + 1]
            guard mark == Unit.space || mark == Unit.lowerX || mark == Unit.upperX else { return nil }
            guard let taskEnd = separated(after: open + 3) else { return nil }
            let line = marked(.task(checked: mark != Unit.space), range: range, markerEnd: taskEnd)
            return NoteMarkdown.Line(
                kind: line.kind, range: line.range, contentRange: line.contentRange,
                markerRange: line.markerRange, checkboxRange: NSRange(location: open, length: 3),
                level: 0)
        }

        /// The marker end when `index` is followed by one space or tab, or by the end of the line.
        private func separated(after index: Int) -> Int? {
            if index == end { return index }
            return Unit.isSpaceOrTab(units[index]) ? index + 1 : nil
        }

        private func run(of unit: UInt16, from index: Int) -> Int {
            units[index..<end].firstIndex { $0 != unit } ?? end
        }

        private func marked(
            _ kind: NoteMarkdown.Line.Kind, range: NSRange, markerEnd: Int
        ) -> NoteMarkdown.Line {
            NoteMarkdown.Line(
                kind: kind, range: range, contentRange: NSRange(markerEnd..<end),
                markerRange: NSRange(start..<markerEnd), checkboxRange: nil, level: 0)
        }

        private func plain(_ kind: NoteMarkdown.Line.Kind, range: NSRange, contentStart: Int)
            -> NoteMarkdown.Line {
            NoteMarkdown.Line(
                kind: kind, range: range, contentRange: NSRange(contentStart..<end), markerRange: nil,
                checkboxRange: nil, level: 0)
        }
    }
}
