import Foundation

/// Finds the inline spans of one line's content; the parser never hands it more than one line.
struct NoteInlineScanner {
    let units: [UInt16]

    private typealias Unit = NoteMarkdownParser.Unit

    /// A bare URL is recognised only when it states its scheme, never from a bare domain.
    static let webPrefixes = ["https://", "http://"]

    /// GFM's trailing punctuation that never belongs to a bare URL.
    private static let autolinkTrailing: Set<UInt16> = Set(".,;:!?*_~".utf16)

    /// Sorted by location, outer spans before inner ones.
    func inlines(in content: Range<Int>) -> [NoteMarkdown.Inline] {
        guard units[content].contains(where: Self.mayStartInline) else { return [] }
        return scan(content, inLabel: false).sorted {
            ($0.range.location, -$0.range.length) < ($1.range.location, -$1.range.length)
        }
    }

    private static func mayStartInline(_ unit: UInt16) -> Bool {
        switch unit {
        case Unit.asterisk, Unit.underscore, Unit.tilde, Unit.backtick, Unit.openBracket,
            Unit.backslash, Unit.colon:
            true
        default:
            false
        }
    }

    private func scan(_ content: Range<Int>, inLabel: Bool) -> [NoteMarkdown.Inline] {
        var found: [NoteMarkdown.Inline] = []
        var blocked = [Bool](repeating: false, count: content.count)
        func block(_ range: Range<Int>) {
            for index in range.clamped(to: content) { blocked[index - content.lowerBound] = true }
        }
        var index = content.lowerBound
        while index < content.upperBound {
            let unit = units[index]
            if unit == Unit.backslash, index + 1 < content.upperBound,
                Unit.isASCIIPunctuation(units[index + 1]) {
                block(index..<index + 2)
                index += 2
            } else if unit == Unit.backtick {
                let span = codeSpan(at: index, in: content)
                if let inline = span.inline { found.append(inline) }
                block(index..<span.end)
                index = span.end
            } else if unit == Unit.openBracket, !inLabel, let link = link(at: index, in: content) {
                let isImage = index > content.lowerBound && units[index - 1] == Unit.exclamation
                if isImage {
                    block((index - 1)..<link.end)
                } else {
                    let label = (index + 1)..<link.labelEnd
                    found.append(
                        NoteMarkdown.Inline(
                            kind: .link(destination: link.destination),
                            range: NSRange(index..<link.end), contentRange: NSRange(label),
                            markerRanges: [
                                NSRange(location: index, length: 1), NSRange(link.labelEnd..<link.end)
                            ]))
                    found += scan(label, inLabel: true)
                    block(index..<link.end)
                }
                index = link.end
            } else if !inLabel, let end = autolinkEnd(at: index, in: content) {
                found.append(
                    NoteMarkdown.Inline(
                        kind: .autolink, range: NSRange(index..<end), contentRange: NSRange(index..<end),
                        markerRanges: []))
                block(index..<end)
                index = end
            } else {
                index += 1
            }
        }
        return found + emphasis(in: content, blocked: blocked)
    }

    // MARK: - Code, links, bare URLs

    /// An unclosed backtick run is plain text, and its end is still where scanning resumes.
    private func codeSpan(at start: Int, in content: Range<Int>) -> (inline: NoteMarkdown.Inline?, end: Int) {
        let openEnd = runEnd(of: Unit.backtick, from: start, in: content)
        let length = openEnd - start
        var index = openEnd
        while index < content.upperBound {
            guard units[index] == Unit.backtick else {
                index += 1
                continue
            }
            let closeEnd = runEnd(of: Unit.backtick, from: index, in: content)
            if closeEnd - index == length {
                let inline = NoteMarkdown.Inline(
                    kind: .code, range: NSRange(start..<closeEnd), contentRange: NSRange(openEnd..<index),
                    markerRanges: [NSRange(start..<openEnd), NSRange(index..<closeEnd)])
                return (inline, closeEnd)
            }
            index = closeEnd
        }
        return (nil, openEnd)
    }

    private func link(
        at open: Int, in content: Range<Int>
    ) -> (labelEnd: Int, end: Int, destination: String)? {
        var depth = 0
        var index = open
        var labelEnd: Int?
        while index < content.upperBound, labelEnd == nil {
            switch units[index] {
            case Unit.backslash: index += 1
            case Unit.openBracket: depth += 1
            case Unit.closeBracket:
                depth -= 1
                if depth == 0 { labelEnd = index }
            default: break
            }
            index += 1
        }
        guard let labelEnd, labelEnd + 1 < content.upperBound, units[labelEnd + 1] == Unit.openParen
        else { return nil }
        var parentheses = 0
        index = labelEnd + 2
        while index < content.upperBound {
            let unit = units[index]
            if Unit.isWhitespace(unit) { return nil }
            if unit == Unit.backslash {
                index += 2
                continue
            }
            if unit == Unit.openParen { parentheses += 1 }
            if unit == Unit.closeParen {
                guard parentheses == 0 else {
                    parentheses -= 1
                    index += 1
                    continue
                }
                let destination = String(decoding: units[(labelEnd + 2)..<index], as: UTF16.self)
                return (labelEnd, index + 1, destination)
            }
            index += 1
        }
        return nil
    }

    private func autolinkEnd(at start: Int, in content: Range<Int>) -> Int? {
        guard units[start] | 0x20 == 0x68 else { return nil }
        if start > content.lowerBound, Unit.isAlphanumeric(units[start - 1]) { return nil }
        guard let schemeEnd = Self.webPrefixes.lazy.compactMap({
            matchesIgnoringCase($0, at: start, in: content)
        }).first
        else { return nil }
        var end = units[schemeEnd..<content.upperBound].firstIndex(where: Unit.isWhitespace)
            ?? content.upperBound
        while end > schemeEnd {
            let last = units[end - 1]
            if Self.autolinkTrailing.contains(last) {
                end -= 1
            } else if last == Unit.closeParen, hasUnmatchedCloser(start..<end) {
                end -= 1
            } else {
                break
            }
        }
        return end > schemeEnd ? end : nil
    }

    private func hasUnmatchedCloser(_ range: Range<Int>) -> Bool {
        let opens = units[range].count { $0 == Unit.openParen }
        let closes = units[range].count { $0 == Unit.closeParen }
        return closes > opens
    }

    private func matchesIgnoringCase(_ prefix: String, at start: Int, in content: Range<Int>) -> Int? {
        var index = start
        for expected in prefix.utf16 {
            guard index < content.upperBound, units[index] | 0x20 == expected | 0x20 else { return nil }
            index += 1
        }
        return index
    }

    private func runEnd(of unit: UInt16, from start: Int, in content: Range<Int>) -> Int {
        units[start..<content.upperBound].firstIndex { $0 != unit } ?? content.upperBound
    }

    // MARK: - Emphasis and strikethrough

    private struct DelimiterRun {
        let marker: UInt16
        var start: Int
        var end: Int
        var length: Int { end - start }
    }

    /// Delimiter runs pair with the nearest open run of the same character, as in CommonMark.
    private func emphasis(in content: Range<Int>, blocked: [Bool]) -> [NoteMarkdown.Inline] {
        var found: [NoteMarkdown.Inline] = []
        var openers: [DelimiterRun] = []
        var index = content.lowerBound
        while index < content.upperBound {
            let marker = units[index]
            guard !blocked[index - content.lowerBound],
                marker == Unit.asterisk || marker == Unit.underscore || marker == Unit.tilde
            else {
                index += 1
                continue
            }
            var end = index + 1
            while end < content.upperBound, units[end] == marker, !blocked[end - content.lowerBound] {
                end += 1
            }
            defer { index = end }
            if marker == Unit.tilde, end - index != 2 { continue }

            let before = index > content.lowerBound ? units[index - 1] : nil
            let after = end < content.upperBound ? units[end] : nil
            var canOpen = after.map { !Unit.isWhitespace($0) } ?? false
            var canClose = before.map { !Unit.isWhitespace($0) } ?? false
            if marker == Unit.underscore {
                canOpen = canOpen && !(before.map(Unit.isAlphanumeric) ?? false)
                canClose = canClose && !(after.map(Unit.isAlphanumeric) ?? false)
            }

            var run = DelimiterRun(marker: marker, start: index, end: end)
            if run.length > 3, canOpen != canClose {
                if canOpen { run.start = run.end - 3 } else { run.end = run.start + 3 }
            }
            while canClose, run.length > 0,
                let openerIndex = openers.lastIndex(where: { $0.marker == marker }) {
                var opener = openers[openerIndex]
                let use = marker == Unit.tilde ? 2 : min(opener.length, run.length, 3)
                let open = (opener.end - use)..<opener.end
                let close = run.start..<(run.start + use)
                found.append(
                    NoteMarkdown.Inline(
                        kind: Self.emphasisKind(marker: marker, length: use),
                        range: NSRange(open.lowerBound..<close.upperBound),
                        contentRange: NSRange(open.upperBound..<close.lowerBound),
                        markerRanges: [NSRange(open), NSRange(close)]))
                opener.end -= use
                run.start += use
                openers.removeSubrange((openerIndex + 1)..<openers.count)
                if opener.length > 0 {
                    openers[openerIndex] = opener
                } else {
                    openers.remove(at: openerIndex)
                }
            }
            if canOpen, run.length > 0 { openers.append(run) }
        }
        return found
    }

    private static func emphasisKind(marker: UInt16, length: Int) -> NoteMarkdown.Inline.Kind {
        guard marker != Unit.tilde else { return .strikethrough }
        switch length {
        case 1: return .emphasis
        case 2: return .strong
        default: return .strongEmphasis
        }
    }
}
