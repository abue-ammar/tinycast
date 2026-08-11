import Foundation

struct NoteMarkdownPresentation: Sendable, Equatable {
    struct Construct: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case heading(level: Int)
            case strong
            case emphasis
            case strongEmphasis
            case strikethrough
            case inlineCode
            case link(destination: String)
            case image
            case blockquote
            case unorderedList
            case orderedList
            case task(checked: Bool)
            case horizontalRule
            case codeBlock(language: String?)
        }

        let kind: Kind
        let range: NSRange
        let contentRange: NSRange
        let markerRanges: [NSRange]
    }

    let sourceLength: Int
    let constructs: [Construct]

    func activeConstruct(at location: Int) -> Construct? {
        constructs
            .filter { location >= $0.range.location && location <= NSMaxRange($0.range) }
            .min { lhs, rhs in
                if lhs.range.length == rhs.range.length {
                    return lhs.range.location > rhs.range.location
                }
                return lhs.range.length < rhs.range.length
            }
    }
}

enum NoteMarkdownParser {
    private struct Line {
        let fullRange: NSRange
        let contentRange: NSRange
    }

    private struct Fence {
        let character: unichar
        let count: Int
        let line: Line
        let language: String?
    }

    private struct OccupiedRange {
        let range: NSRange
        let nestedRange: NSRange?
    }

    static func parse(_ source: String) -> NoteMarkdownPresentation {
        let text = source as NSString
        guard text.length > 0 else {
            return NoteMarkdownPresentation(sourceLength: 0, constructs: [])
        }

        let lines = lines(in: text)
        var constructs: [NoteMarkdownPresentation.Construct] = []
        var fence: Fence?

        for line in lines {
            if let openFence = fence {
                if isClosingFence(line, for: openFence, text: text) {
                    constructs.append(codeBlock(from: openFence, through: line, text: text))
                    fence = nil
                }
                continue
            }
            if let opened = openingFence(on: line, text: text) {
                fence = opened
                continue
            }
            scanLine(line, text: text, into: &constructs)
        }

        if let fence {
            let range = NSRange(
                location: fence.line.fullRange.location,
                length: text.length - fence.line.fullRange.location)
            let contentStart = NSMaxRange(fence.line.fullRange)
            constructs.append(
                .init(
                    kind: .codeBlock(language: fence.language),
                    range: range,
                    contentRange: NSRange(
                        location: contentStart,
                        length: max(0, text.length - contentStart)),
                    markerRanges: [fence.line.fullRange]))
        }

        constructs.sort {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }
        return NoteMarkdownPresentation(sourceLength: text.length, constructs: constructs)
    }

    static func update(
        previousSource: String,
        source: String,
        presentation: NoteMarkdownPresentation,
        editedRange: NSRange,
        replacement: String
    ) -> NoteMarkdownPresentation {
        let previous = previousSource as NSString
        let current = source as NSString
        guard !replacement.contains(where: { $0.isNewline }),
            editedRange.location != NSNotFound,
            editedRange.location >= 0,
            NSMaxRange(editedRange) <= previous.length,
            !previous.substring(with: editedRange).contains(where: { $0.isNewline }),
            let oldLine = coveringLineRange(in: previous, at: editedRange.location),
            let newLine = coveringLineRange(in: current, at: editedRange.location)
        else { return parse(source) }

        let oldLineSource = previous.substring(with: oldLine)
        let newLineSource = current.substring(with: newLine)
        guard !containsFenceDelimiter(oldLineSource), !containsFenceDelimiter(newLineSource),
            !presentation.constructs.contains(where: {
                if case .codeBlock = $0.kind {
                    return NSIntersectionRange($0.range, oldLine).length > 0
                        || NSLocationInRange(editedRange.location, $0.range)
                }
                return false
            })
        else { return parse(source) }

        let delta = current.length - previous.length
        var constructs: [NoteMarkdownPresentation.Construct] = []
        constructs.reserveCapacity(presentation.constructs.count + 4)
        for construct in presentation.constructs {
            if NSMaxRange(construct.range) <= oldLine.location {
                constructs.append(construct)
            } else if construct.range.location >= NSMaxRange(oldLine) {
                constructs.append(construct.shifted(by: delta))
            }
        }
        constructs.append(contentsOf: parse(newLineSource).constructs.map {
            $0.shifted(by: newLine.location)
        })
        constructs.sort {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }
        return NoteMarkdownPresentation(sourceLength: current.length, constructs: constructs)
    }

    private static func scanLine(
        _ line: Line,
        text: NSString,
        into constructs: inout [NoteMarkdownPresentation.Construct]
    ) {
        guard line.contentRange.length > 0 else { return }
        let indentation = leadingWhitespace(in: line.contentRange, text: text)
        var contentStart = line.contentRange.location + indentation
        let lineEnd = NSMaxRange(line.contentRange)
        guard contentStart < lineEnd else { return }

        if let heading = heading(at: contentStart, lineEnd: lineEnd, text: text) {
            constructs.append(heading)
            contentStart = heading.contentRange.location
        }

        while contentStart < lineEnd, text.character(at: contentStart) == 0x3E {
            let markerLength = contentStart + 1 < lineEnd && text.character(at: contentStart + 1) == 0x20
                ? 2 : 1
            constructs.append(
                .init(
                    kind: .blockquote,
                    range: NSRange(location: contentStart, length: lineEnd - contentStart),
                    contentRange: NSRange(
                        location: contentStart + markerLength,
                        length: lineEnd - contentStart - markerLength),
                    markerRanges: [NSRange(location: contentStart, length: markerLength)]))
            contentStart += markerLength
        }

        if isHorizontalRule(from: contentStart, to: lineEnd, text: text) {
            let range = NSRange(location: contentStart, length: lineEnd - contentStart)
            constructs.append(
                .init(
                    kind: .horizontalRule,
                    range: range,
                    contentRange: range,
                    markerRanges: [range]))
            return
        }

        if let list = listMarker(at: contentStart, lineEnd: lineEnd, text: text) {
            let markerEnd = NSMaxRange(list.range)
            constructs.append(
                .init(
                    kind: list.ordered ? .orderedList : .unorderedList,
                    range: NSRange(location: contentStart, length: lineEnd - contentStart),
                    contentRange: NSRange(
                        location: markerEnd + 1,
                        length: max(0, lineEnd - markerEnd - 1)),
                    markerRanges: [list.range]))
            contentStart = markerEnd + 1
            if let task = taskMarker(at: contentStart, lineEnd: lineEnd, text: text) {
                constructs.append(
                    .init(
                        kind: .task(checked: task.checked),
                        range: NSRange(location: task.range.location, length: lineEnd - task.range.location),
                        contentRange: NSRange(
                            location: NSMaxRange(task.range),
                            length: lineEnd - NSMaxRange(task.range)),
                        markerRanges: [task.range]))
                contentStart = NSMaxRange(task.range)
                if contentStart < lineEnd, text.character(at: contentStart) == 0x20 {
                    contentStart += 1
                }
            }
        }

        guard contentStart < lineEnd else { return }
        scanInline(
            NSRange(location: contentStart, length: lineEnd - contentStart),
            text: text,
            into: &constructs)
    }

    private static func scanInline(
        _ range: NSRange,
        text: NSString,
        into constructs: inout [NoteMarkdownPresentation.Construct]
    ) {
        var occupied: [OccupiedRange] = []
        let constructStart = constructs.count
        appendLinks(in: range, text: text, occupied: &occupied, into: &constructs)
        appendPaired(
            token: "`", kind: .inlineCode, in: range, text: text,
            allowsNested: false, occupied: &occupied, into: &constructs)
        appendPaired(
            token: "***", kind: .strongEmphasis, in: range, text: text,
            allowsNested: true, occupied: &occupied, into: &constructs)
        appendPaired(
            token: "___", kind: .strongEmphasis, in: range, text: text,
            allowsNested: true, occupied: &occupied, into: &constructs)
        appendPaired(
            token: "**", kind: .strong, in: range, text: text,
            allowsNested: true, occupied: &occupied, into: &constructs)
        appendPaired(
            token: "__", kind: .strong, in: range, text: text,
            allowsNested: true, occupied: &occupied, into: &constructs)
        appendPaired(
            token: "~~", kind: .strikethrough, in: range, text: text,
            allowsNested: true, occupied: &occupied, into: &constructs)
        appendPaired(
            token: "*", kind: .emphasis, in: range, text: text,
            allowsNested: true, occupied: &occupied, into: &constructs)
        appendPaired(
            token: "_", kind: .emphasis, in: range, text: text,
            allowsNested: true, occupied: &occupied, into: &constructs)
        let links = constructs[constructStart...].filter {
            if case .link = $0.kind { return true }
            return false
        }
        for link in links where link.contentRange.length > 0 {
            scanInline(link.contentRange, text: text, into: &constructs)
        }
    }

    private static func appendLinks(
        in range: NSRange,
        text: NSString,
        occupied: inout [OccupiedRange],
        into constructs: inout [NoteMarkdownPresentation.Construct]
    ) {
        var index = range.location
        let end = NSMaxRange(range)
        while index < end {
            guard text.character(at: index) == 0x5B, !isEscaped(index, text: text) else {
                index += 1
                continue
            }
            let image = index > range.location && text.character(at: index - 1) == 0x21
                && !isEscaped(index - 1, text: text)
            guard let labelClose = matchingBracket(from: index, end: end, text: text),
                labelClose + 1 < end,
                text.character(at: labelClose + 1) == 0x28,
                let destinationClose = matchingParenthesis(
                    from: labelClose + 1, end: end, text: text)
            else {
                index += 1
                continue
            }
            let start = image ? index - 1 : index
            let constructRange = NSRange(location: start, length: destinationClose - start + 1)
            let labelRange = NSRange(location: index + 1, length: labelClose - index - 1)
            let destinationRange = NSRange(
                location: labelClose + 2,
                length: destinationClose - labelClose - 2)
            let rawDestination = text.substring(with: destinationRange)
            let destination = destinationWithoutTitle(rawDestination)
            constructs.append(
                .init(
                    kind: image ? .image : .link(destination: destination),
                    range: constructRange,
                    contentRange: labelRange,
                    markerRanges: image
                        ? []
                        : [
                            NSRange(location: index, length: 1),
                            NSRange(location: labelClose, length: destinationClose - labelClose + 1)
                        ]))
            occupied.append(OccupiedRange(range: constructRange, nestedRange: nil))
            index = destinationClose + 1
        }
    }

    private static func appendPaired(
        token: String,
        kind: NoteMarkdownPresentation.Construct.Kind,
        in range: NSRange,
        text: NSString,
        allowsNested: Bool,
        occupied: inout [OccupiedRange],
        into constructs: inout [NoteMarkdownPresentation.Construct]
    ) {
        let tokenLength = (token as NSString).length
        var index = range.location
        let end = NSMaxRange(range)
        while index + tokenLength <= end {
            guard matches(token, at: index, text: text), !isEscaped(index, text: text),
                markerIsAvailable(at: index, length: tokenLength, occupied: occupied)
            else {
                index += 1
                continue
            }
            if token == "_", isIntrawordUnderscore(at: index, length: tokenLength, text: text) {
                index += tokenLength
                continue
            }
            var closing = index + tokenLength
            while closing + tokenLength <= end {
                if matches(token, at: closing, text: text), !isEscaped(closing, text: text),
                    markerIsAvailable(at: closing, length: tokenLength, occupied: occupied)
                {
                    break
                }
                closing += 1
            }
            guard closing + tokenLength <= end, closing > index + tokenLength else {
                index += tokenLength
                continue
            }
            let constructRange = NSRange(
                location: index,
                length: closing + tokenLength - index)
            let contentRange = NSRange(
                location: index + tokenLength,
                length: closing - index - tokenLength)
            guard occupied.allSatisfy({ existing in
                nestedRangesAreValid(
                    candidate: constructRange,
                    content: contentRange,
                    existing: existing)
            }) else {
                index += tokenLength
                continue
            }
            constructs.append(
                .init(
                    kind: kind,
                    range: constructRange,
                    contentRange: contentRange,
                    markerRanges: [
                        NSRange(location: index, length: tokenLength),
                        NSRange(location: closing, length: tokenLength)
                    ]))
            occupied.append(
                OccupiedRange(
                    range: constructRange,
                    nestedRange: allowsNested ? contentRange : nil))
            index = closing + tokenLength
        }
    }

    private static func markerIsAvailable(
        at location: Int,
        length: Int,
        occupied: [OccupiedRange]
    ) -> Bool {
        let marker = NSRange(location: location, length: length)
        return occupied.allSatisfy { existing in
            NSIntersectionRange(marker, existing.range).length == 0
                || existing.nestedRange.map { contains($0, marker) } == true
        }
    }

    private static func nestedRangesAreValid(
        candidate: NSRange,
        content: NSRange,
        existing: OccupiedRange
    ) -> Bool {
        guard NSIntersectionRange(candidate, existing.range).length > 0 else { return true }
        if contains(content, existing.range) { return true }
        if let nestedRange = existing.nestedRange, contains(nestedRange, candidate) { return true }
        return false
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer.location <= inner.location && NSMaxRange(outer) >= NSMaxRange(inner)
    }

    private static func lines(in text: NSString) -> [Line] {
        var result: [Line] = []
        var location = 0
        while location < text.length {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getLineStart(
                &start, end: &end, contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0))
            result.append(
                Line(
                    fullRange: NSRange(location: start, length: end - start),
                    contentRange: NSRange(location: start, length: contentsEnd - start)))
            location = max(end, location + 1)
        }
        return result
    }

    private static func coveringLineRange(in text: NSString, at location: Int) -> NSRange? {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let clamped = min(max(0, location), text.length - 1)
        return text.lineRange(for: NSRange(location: clamped, length: 0))
    }

    private static func containsFenceDelimiter(_ line: String) -> Bool {
        line.contains("```") || line.contains("~~~")
    }

    private static func openingFence(on line: Line, text: NSString) -> Fence? {
        let start = line.contentRange.location + leadingWhitespace(in: line.contentRange, text: text)
        guard start < NSMaxRange(line.contentRange) else { return nil }
        let character = text.character(at: start)
        guard character == 0x60 || character == 0x7E else { return nil }
        let count = repeatedCount(character, at: start, end: NSMaxRange(line.contentRange), text: text)
        guard count >= 3 else { return nil }
        let languageRange = NSRange(
            location: start + count,
            length: NSMaxRange(line.contentRange) - start - count)
        let language = text.substring(with: languageRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Fence(
            character: character,
            count: count,
            line: line,
            language: language.isEmpty ? nil : language)
    }

    private static func isClosingFence(_ line: Line, for fence: Fence, text: NSString) -> Bool {
        let start = line.contentRange.location + leadingWhitespace(in: line.contentRange, text: text)
        guard start < NSMaxRange(line.contentRange), text.character(at: start) == fence.character else {
            return false
        }
        let count = repeatedCount(
            fence.character, at: start, end: NSMaxRange(line.contentRange), text: text)
        guard count >= fence.count else { return false }
        let remainder = NSRange(
            location: start + count,
            length: NSMaxRange(line.contentRange) - start - count)
        return text.substring(with: remainder).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func codeBlock(from fence: Fence, through line: Line, text: NSString)
        -> NoteMarkdownPresentation.Construct
    {
        let range = NSRange(
            location: fence.line.fullRange.location,
            length: NSMaxRange(line.fullRange) - fence.line.fullRange.location)
        let contentStart = NSMaxRange(fence.line.fullRange)
        return .init(
            kind: .codeBlock(language: fence.language),
            range: range,
            contentRange: NSRange(
                location: contentStart,
                length: max(0, line.fullRange.location - contentStart)),
            markerRanges: [fence.line.fullRange, line.fullRange])
    }

    private static func heading(at start: Int, lineEnd: Int, text: NSString)
        -> NoteMarkdownPresentation.Construct?
    {
        var level = 0
        while start + level < lineEnd, level < 6, text.character(at: start + level) == 0x23 {
            level += 1
        }
        guard level > 0, start + level < lineEnd, text.character(at: start + level) == 0x20 else {
            return nil
        }
        let marker = NSRange(location: start, length: level + 1)
        return .init(
            kind: .heading(level: level),
            range: NSRange(location: start, length: lineEnd - start),
            contentRange: NSRange(location: NSMaxRange(marker), length: lineEnd - NSMaxRange(marker)),
            markerRanges: [marker])
    }

    private static func listMarker(at start: Int, lineEnd: Int, text: NSString)
        -> (range: NSRange, ordered: Bool)?
    {
        guard start + 1 < lineEnd else { return nil }
        let first = text.character(at: start)
        if [0x2D, 0x2A, 0x2B].contains(first), text.character(at: start + 1) == 0x20 {
            return (NSRange(location: start, length: 1), false)
        }
        var index = start
        while index < lineEnd {
            let character = text.character(at: index)
            guard character >= 0x30, character <= 0x39 else { break }
            index += 1
        }
        guard index > start, index + 1 < lineEnd,
            text.character(at: index) == 0x2E,
            text.character(at: index + 1) == 0x20
        else { return nil }
        return (NSRange(location: start, length: index - start + 1), true)
    }

    private static func taskMarker(at start: Int, lineEnd: Int, text: NSString)
        -> (range: NSRange, checked: Bool)?
    {
        guard start + 3 <= lineEnd,
            text.character(at: start) == 0x5B,
            text.character(at: start + 2) == 0x5D
        else { return nil }
        let value = text.character(at: start + 1)
        guard value == 0x20 || value == 0x78 || value == 0x58 else { return nil }
        return (NSRange(location: start, length: 3), value != 0x20)
    }

    private static func isHorizontalRule(from start: Int, to end: Int, text: NSString) -> Bool {
        var marker: unichar?
        var count = 0
        for index in start..<end {
            let character = text.character(at: index)
            if character == 0x20 || character == 0x09 { continue }
            guard character == 0x2A || character == 0x2D || character == 0x5F else { return false }
            if let marker, marker != character { return false }
            marker = character
            count += 1
        }
        return count >= 3
    }

    private static func leadingWhitespace(in range: NSRange, text: NSString) -> Int {
        var count = 0
        while count < range.length {
            let character = text.character(at: range.location + count)
            guard character == 0x20 || character == 0x09 else { break }
            count += 1
        }
        return count
    }

    private static func repeatedCount(
        _ character: unichar,
        at start: Int,
        end: Int,
        text: NSString
    ) -> Int {
        var index = start
        while index < end, text.character(at: index) == character { index += 1 }
        return index - start
    }

    private static func matchingBracket(from start: Int, end: Int, text: NSString) -> Int? {
        var depth = 0
        var index = start
        while index < end {
            let character = text.character(at: index)
            if !isEscaped(index, text: text) {
                if character == 0x5B { depth += 1 }
                if character == 0x5D {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index += 1
        }
        return nil
    }

    private static func matchingParenthesis(from start: Int, end: Int, text: NSString) -> Int? {
        var depth = 0
        var index = start
        var quote: unichar?
        while index < end {
            let character = text.character(at: index)
            if isEscaped(index, text: text) {
                index += 1
                continue
            }
            if character == 0x22 || character == 0x27 {
                quote = quote == character ? nil : quote ?? character
            } else if quote == nil {
                if character == 0x28 { depth += 1 }
                if character == 0x29 {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index += 1
        }
        return nil
    }

    private static func destinationWithoutTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let quote = trimmed.lastIndex(where: { $0 == "\"" || $0 == "'" }) else {
            return trimmed
        }
        let before = trimmed[..<quote]
        guard let opening = before.lastIndex(of: trimmed[quote]),
            before[..<opening].last?.isWhitespace == true
        else { return trimmed }
        return before[..<opening].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ token: String, at location: Int, text: NSString) -> Bool {
        let length = (token as NSString).length
        guard location + length <= text.length else { return false }
        return text.substring(with: NSRange(location: location, length: length)) == token
    }

    private static func isEscaped(_ location: Int, text: NSString) -> Bool {
        guard location > 0 else { return false }
        var slashes = 0
        var index = location - 1
        while text.character(at: index) == 0x5C {
            slashes += 1
            guard index > 0 else { break }
            index -= 1
        }
        return slashes % 2 == 1
    }

    private static func isIntrawordUnderscore(at location: Int, length: Int, text: NSString) -> Bool {
        guard location > 0, location + length < text.length else { return false }
        let before = Unicode.Scalar(text.character(at: location - 1))
        let after = Unicode.Scalar(text.character(at: location + length))
        return before.map(CharacterSet.alphanumerics.contains) == true
            && after.map(CharacterSet.alphanumerics.contains) == true
    }
}

private extension NoteMarkdownPresentation.Construct {
    func shifted(by delta: Int) -> NoteMarkdownPresentation.Construct {
        .init(
            kind: kind,
            range: NSRange(location: range.location + delta, length: range.length),
            contentRange: NSRange(
                location: contentRange.location + delta,
                length: contentRange.length),
            markerRanges: markerRanges.map {
                NSRange(location: $0.location + delta, length: $0.length)
            })
    }
}
