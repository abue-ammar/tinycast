import Foundation

struct SyntaxMarkupLexer {
    private typealias Unit = SyntaxUnit

    private let chars: [UInt16]
    private(set) var tokens: [SyntaxToken] = []
    private var index = 0

    private static let commentOpen = Array("<!--".utf16)
    private static let commentClose = Array("-->".utf16)
    private static let cdataOpen = Array("<![CDATA[".utf16)
    private static let cdataClose = Array("]]>".utf16)
    private static let declarationOpen = Array("<!".utf16)
    private static let instructionOpen = Array("<?".utf16)
    private static let angleClose = Array(">".utf16)

    init(_ chars: [UInt16]) {
        self.chars = chars
    }

    mutating func run() {
        while index < chars.count {
            if chars[index] == Unit.lessThan {
                scanAngle()
            } else if chars[index] == Unit.ampersand {
                scanEntity()
            } else {
                index += 1
            }
        }
    }

    private mutating func scanAngle() {
        if matches(Self.commentOpen) {
            scan(until: Self.commentClose, .comment)
        } else if matches(Self.cdataOpen) {
            scan(until: Self.cdataClose, .string)
        } else if matches(Self.declarationOpen) || matches(Self.instructionOpen) {
            scan(until: Self.angleClose, .attribute)
        } else if startsTag() {
            scanTag()
        } else {
            index += 1
        }
    }

    private func matches(_ pattern: [UInt16]) -> Bool {
        Unit.matches(pattern, in: chars, at: index)
    }

    private func unit(at position: Int) -> UInt16? {
        position < chars.count ? chars[position] : nil
    }

    private mutating func emit(from start: Int, _ kind: SyntaxKind) {
        guard index > start else { return }
        tokens.append(SyntaxToken(range: NSRange(location: start, length: index - start), kind: kind))
    }

    private mutating func scan(until terminator: [UInt16], _ kind: SyntaxKind) {
        let start = index
        while index < chars.count, !matches(terminator) { index += 1 }
        index = min(index + terminator.count, chars.count)
        emit(from: start, kind)
    }

    private func startsTag() -> Bool {
        var position = index + 1
        if unit(at: position) == Unit.slash { position += 1 }
        return unit(at: position).map(Unit.isLetter) ?? false
    }

    private mutating func scanEntity() {
        let start = index
        index += 1
        while let unit = unit(at: index), Unit.isIdentPart(unit) || unit == Unit.hash { index += 1 }
        guard unit(at: index) == Unit.semicolon, index - start > 1 else {
            index = start + 1
            return
        }
        index += 1
        emit(from: start, .constant)
    }

    private mutating func scanTag() {
        let start = index
        index += 1
        let isClosing = unit(at: index) == Unit.slash
        if isClosing { index += 1 }
        let nameStart = index
        while let unit = unit(at: index),
            Unit.isIdentPart(unit) || unit == Unit.minus
                || unit == Unit.colon || unit == Unit.dot
        {
            index += 1
        }
        let name = Unit.text(chars[nameStart..<index]).lowercased()
        emit(from: start, .keyword)
        scanAttributes()
        guard !isClosing, name == "script" || name == "style" else { return }
        let embedded: SyntaxLanguage = name == "script" ? .code(.javascript) : .stylesheet
        scanEmbedded(closing: "</\(name)", language: embedded)
    }

    private mutating func scanAttributes() {
        while index < chars.count {
            let unit = chars[index]
            let start = index
            if unit == Unit.greaterThan {
                index += 1
                emit(from: start, .keyword)
                return
            } else if unit == Unit.slash, self.unit(at: index + 1) == Unit.greaterThan {
                index += 2
                emit(from: start, .keyword)
                return
            } else if unit == Unit.lessThan {
                return
            } else if Unit.isQuote(unit) {
                index += 1
                while index < chars.count, chars[index] != unit { index += 1 }
                index = min(index + 1, chars.count)
                emit(from: start, .string)
            } else if unit == Unit.equals {
                index += 1
                scanUnquotedValue()
            } else if Unit.isSpace(unit) || unit == Unit.newline {
                index += 1
            } else {
                while let unit = self.unit(at: index), !Unit.isSpace(unit), unit != Unit.newline,
                    unit != Unit.equals, unit != Unit.slash, unit != Unit.greaterThan,
                    !Unit.isQuote(unit), unit != Unit.lessThan
                {
                    index += 1
                }
                if index == start { index += 1 }
                emit(from: start, .property)
            }
        }
    }

    private mutating func scanUnquotedValue() {
        while let unit = unit(at: index), Unit.isSpace(unit) { index += 1 }
        let start = index
        while let unit = unit(at: index), !Unit.isSpace(unit), unit != Unit.newline,
            unit != Unit.greaterThan, !Unit.isQuote(unit)
        {
            index += 1
        }
        emit(from: start, .string)
    }

    private mutating func scanEmbedded(closing: String, language: SyntaxLanguage) {
        let closer = Array(closing.lowercased().utf16)
        let start = index
        var end = start
        while end < chars.count, !Unit.matches(closer, in: chars, at: end) { end += 1 }
        guard end > start else { return }
        for token in SyntaxHighlighter.tokens(in: Array(chars[start..<end]), language: language) {
            let range = NSRange(location: token.range.location + start, length: token.range.length)
            tokens.append(SyntaxToken(range: range, kind: token.kind))
        }
        index = end
    }
}

struct SyntaxStylesheetLexer {
    private typealias Unit = SyntaxUnit

    private let chars: [UInt16]
    private(set) var tokens: [SyntaxToken] = []
    private var index = 0
    private var statement = Statement.pending
    private var parenDepth = 0

    private enum Statement {
        case pending
        case selector
        case declaration
    }

    init(_ chars: [UInt16]) {
        self.chars = chars
    }

    mutating func run() {
        while index < chars.count {
            let unit = chars[index]
            if unit == Unit.newline || Unit.isSpace(unit) {
                index += 1
                continue
            }
            if statement == .pending { statement = classifyStatement() }
            scanToken(unit)
        }
    }

    private func unit(at position: Int) -> UInt16? {
        position < chars.count ? chars[position] : nil
    }

    private mutating func emit(from start: Int, _ kind: SyntaxKind) {
        guard index > start else { return }
        tokens.append(SyntaxToken(range: NSRange(location: start, length: index - start), kind: kind))
    }

    private func classifyStatement() -> Statement {
        var position = index
        var depth = 0
        while let unit = unit(at: position) {
            if unit == Unit.openParen { depth += 1 }
            if unit == Unit.closeParen { depth = max(depth - 1, 0) }
            if depth == 0 {
                if unit == Unit.openBrace { return .selector }
                if unit == Unit.semicolon || unit == Unit.closeBrace { return .declaration }
            }
            position += 1
        }
        return .declaration
    }

    private mutating func scanToken(_ unit: UInt16) {
        let start = index
        if unit == Unit.slash, self.unit(at: index + 1) == Unit.star {
            index += 2
            while index < chars.count, !(chars[index] == Unit.star && self.unit(at: index + 1) == Unit.slash)
            {
                index += 1
            }
            index = min(index + 2, chars.count)
            emit(from: start, .comment)
        } else if unit == Unit.slash, self.unit(at: index + 1) == Unit.slash {
            while index < chars.count, chars[index] != Unit.newline { index += 1 }
            emit(from: start, .comment)
        } else if Unit.isQuote(unit) {
            index += 1
            while index < chars.count, chars[index] != unit, chars[index] != Unit.newline {
                index += chars[index] == Unit.backslash ? 2 : 1
            }
            index = min(index + 1, chars.count)
            emit(from: start, .string)
        } else if unit == Unit.openBrace || unit == Unit.semicolon || unit == Unit.closeBrace {
            index += 1
            statement = .pending
            parenDepth = 0
        } else if unit == Unit.openParen || unit == Unit.closeParen {
            index += 1
            parenDepth = max(parenDepth + (unit == Unit.openParen ? 1 : -1), 0)
        } else if unit == Unit.at {
            index += 1
            scanName()
            emit(from: start, .keyword)
        } else if unit == Unit.hash {
            scanHash()
        } else if Unit.isDigit(unit)
            || (unit == Unit.dot && (self.unit(at: index + 1).map(Unit.isDigit) ?? false))
        {
            scanLength()
        } else if unit == Unit.bang {
            index += 1
            scanName()
            emit(from: start, .keyword)
        } else if unit == Unit.dot, statement == .selector {
            index += 1
            scanName()
            emit(from: start, .type)
        } else if unit == Unit.colon, statement == .selector, parenDepth == 0 {
            while self.unit(at: index) == Unit.colon { index += 1 }
            scanName()
            emit(from: start, .attribute)
        } else if unit == Unit.dollar {
            index += 1
            scanName()
            emit(from: start, .property)
        } else if isNameStart(unit) {
            scanIdentifier()
        } else {
            index += 1
        }
    }

    private func isNameStart(_ unit: UInt16) -> Bool {
        Unit.isIdentStart(unit)
            || (unit == Unit.minus
                && (self.unit(at: index + 1).map { Unit.isIdentStart($0) || $0 == Unit.minus } ?? false))
    }

    private mutating func scanName() {
        while let unit = unit(at: index), Unit.isIdentPart(unit) || unit == Unit.minus { index += 1 }
    }

    private mutating func scanIdentifier() {
        let start = index
        scanName()
        var position = index
        while let unit = unit(at: position), Unit.isSpace(unit) { position += 1 }
        let next = unit(at: position)
        if next == Unit.openParen {
            emit(from: start, .function)
            if Unit.text(chars[start..<index]).lowercased() == "url" { scanURL(at: position) }
        } else if next == Unit.colon, statement == .declaration, unit(at: position + 1) != Unit.colon {
            emit(from: start, .property)
        } else if statement == .selector, parenDepth == 0 {
            emit(from: start, .keyword)
        }
    }

    private mutating func scanURL(at open: Int) {
        guard let first = unit(at: open + 1), !Unit.isQuote(first) else { return }
        var end = open + 1
        while end < chars.count, chars[end] != Unit.closeParen { end += 1 }
        index = end
    }

    private mutating func scanHash() {
        let start = index
        index += 1
        scanName()
        let length = index - start - 1
        let isColour =
            statement == .declaration
            && [3, 4, 6, 8].contains(length) && chars[(start + 1)..<index].allSatisfy(Unit.isHex)
        emit(from: start, isColour ? .number : .type)
    }

    private mutating func scanLength() {
        let start = index
        while let unit = unit(at: index), Unit.isDigit(unit) || unit == Unit.dot { index += 1 }
        while let unit = unit(at: index), Unit.isLetter(unit) || unit == Unit.percent { index += 1 }
        emit(from: start, .number)
    }
}

enum SyntaxDiffLexer {
    static func tokens(in chars: [UInt16]) -> [SyntaxToken] {
        var tokens: [SyntaxToken] = []
        var start = 0
        while start < chars.count {
            var end = start
            while end < chars.count, chars[end] != SyntaxUnit.newline { end += 1 }
            if let kind = kind(of: chars[start..<end]) {
                tokens.append(SyntaxToken(range: NSRange(location: start, length: end - start), kind: kind))
            }
            start = end + 1
        }
        return tokens
    }

    private static func kind(of line: ArraySlice<UInt16>) -> SyntaxKind? {
        let head = SyntaxUnit.text(line.prefix(5))
        if ["+++", "---", "diff", "index"].contains(where: head.hasPrefix) { return .comment }
        if head.hasPrefix("@@") { return .type }
        guard let first = line.first else { return nil }
        switch first {
        case SyntaxUnit.plus: return .inserted
        case SyntaxUnit.minus: return .deleted
        default: return nil
        }
    }
}
