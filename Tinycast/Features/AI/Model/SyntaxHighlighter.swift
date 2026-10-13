import Foundation

enum SyntaxHighlighter {
    /// Highlighting reruns on every flush of a streaming reply, so a huge block stays plain.
    static let sizeLimit = 40_000

    static func tokens(in code: String, language: String?) -> [SyntaxToken] {
        guard let language = SyntaxLanguage(named: language) else { return [] }
        let units = Array(code.utf16)
        guard units.count <= sizeLimit else { return [] }
        return tokens(in: units, language: language)
    }

    static func tokens(in units: [UInt16], language: SyntaxLanguage) -> [SyntaxToken] {
        switch language {
        case .code(let grammar):
            var scanner = SyntaxLexer(units, grammar: grammar)
            scanner.run()
            return scanner.tokens
        case .markup:
            var scanner = SyntaxMarkupLexer(units)
            scanner.run()
            return scanner.tokens
        case .stylesheet:
            var scanner = SyntaxStylesheetLexer(units)
            scanner.run()
            return scanner.tokens
        case .diff:
            return SyntaxDiffLexer.tokens(in: units)
        }
    }
}

enum SyntaxUnit {
    static let newline = unit("\n")
    static let space = unit(" ")
    static let tab = unit("\t")
    static let quote = unit("\"")
    static let apostrophe = unit("'")
    static let backslash = unit("\\")
    static let slash = unit("/")
    static let star = unit("*")
    static let hash = unit("#")
    static let dollar = unit("$")
    static let at = unit("@")
    static let dot = unit(".")
    static let colon = unit(":")
    static let equals = unit("=")
    static let minus = unit("-")
    static let plus = unit("+")
    static let underscore = unit("_")
    static let bang = unit("!")
    static let lessThan = unit("<")
    static let greaterThan = unit(">")
    static let openParen = unit("(")
    static let closeParen = unit(")")
    static let openBrace = unit("{")
    static let closeBrace = unit("}")
    static let openBracket = unit("[")
    static let closeBracket = unit("]")
    static let semicolon = unit(";")
    static let ampersand = unit("&")
    static let pipe = unit("|")
    static let percent = unit("%")

    private static func unit(_ scalar: Unicode.Scalar) -> UInt16 { UInt16(scalar.value) }

    static func isSpace(_ unit: UInt16) -> Bool { unit == space || unit == tab || unit == 13 }
    static func isDigit(_ unit: UInt16) -> Bool { unit >= 48 && unit <= 57 }
    static func isLetter(_ unit: UInt16) -> Bool {
        (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122) || unit >= 128
    }
    static func isUpper(_ unit: UInt16) -> Bool { unit >= 65 && unit <= 90 }
    static func isIdentStart(_ unit: UInt16) -> Bool { isLetter(unit) || unit == underscore }
    static func isIdentPart(_ unit: UInt16) -> Bool { isIdentStart(unit) || isDigit(unit) }
    static func isQuote(_ unit: UInt16) -> Bool { unit == quote || unit == apostrophe }
    static func isHex(_ unit: UInt16) -> Bool {
        isDigit(unit) || (unit >= 65 && unit <= 70) || (unit >= 97 && unit <= 102)
    }

    static func matches(_ pattern: [UInt16], in units: [UInt16], at index: Int) -> Bool {
        guard index + pattern.count <= units.count else { return false }
        for offset in pattern.indices where units[index + offset] != pattern[offset] { return false }
        return true
    }

    static func text(_ units: ArraySlice<UInt16>) -> String {
        String(decoding: units, as: UTF16.self)
    }
}

struct SyntaxLexer {
    private typealias Unit = SyntaxUnit

    private let chars: [UInt16]
    private let grammar: SyntaxGrammar
    private(set) var tokens: [SyntaxToken] = []
    private var index = 0
    private var lineHasToken = false
    private var previousWord: String?

    private static let longestKnownWord = 24
    private static let shellCommandWords: Set<String> = [
        "if", "then", "else", "elif", "do", "while", "until", "time", "sudo"
    ]
    private static let statementModifiers: Set<String> = ["export", "declare", "pub"]

    init(_ chars: [UInt16], grammar: SyntaxGrammar) {
        self.chars = chars
        self.grammar = grammar
    }

    mutating func run() {
        while index < chars.count {
            let unit = chars[index]
            if unit == Unit.newline {
                index += 1
                lineHasToken = false
                previousWord = nil
            } else if Unit.isSpace(unit) {
                index += 1
            } else {
                let before = previousWord
                previousWord = nil
                scanToken(after: before)
                lineHasToken = true
            }
        }
    }

    private func has(_ option: SyntaxGrammar.Options) -> Bool { grammar.options.contains(option) }

    private func matches(_ pattern: [UInt16], at position: Int) -> Bool {
        Unit.matches(pattern, in: chars, at: position)
    }

    private func unit(at position: Int) -> UInt16? {
        position >= 0 && position < chars.count ? chars[position] : nil
    }

    private mutating func emit(from start: Int, to end: Int? = nil, _ kind: SyntaxKind) {
        let end = end ?? index
        guard end > start else { return }
        tokens.append(SyntaxToken(range: NSRange(location: start, length: end - start), kind: kind))
    }

    private mutating func scanToken(after previous: String?) {
        let unit = chars[index]
        if !lineHasToken, grammar.lineKeys != nil, scanLineKey() { return }
        if scanComment() { return }
        if has(.lifetimes), unit == Unit.apostrophe, scanLifetime() { return }
        if scanString(prefix: 0) { return }
        if Unit.isDigit(unit) || (unit == Unit.dot && startsNumberAfterDot()) {
            scanNumber()
        } else if isIdentStart(unit) {
            scanWord(after: previous)
        } else if unit == Unit.at, has(.decorators), scanDecorator() {
            return
        } else if unit == Unit.hash, has(.directives), scanDirective() {
            return
        } else if unit == Unit.dollar, has(.dollarVariables), scanVariable() {
            return
        } else if unit == Unit.minus, has(.shell), scanFlag() {
            return
        } else {
            index += 1
        }
    }

    private func isIdentStart(_ unit: UInt16) -> Bool {
        Unit.isIdentStart(unit) || (unit == Unit.dollar && !has(.dollarVariables))
    }

    private func isIdentPart(_ unit: UInt16) -> Bool {
        Unit.isIdentPart(unit) || (unit == Unit.dollar && !has(.dollarVariables))
    }

    private func startsNumberAfterDot() -> Bool {
        guard let next = self.unit(at: index + 1), Unit.isDigit(next) else { return false }
        guard let before = self.unit(at: index - 1) else { return true }
        return !isIdentPart(before) && before != Unit.closeParen && before != Unit.closeBracket
    }

    // MARK: Comments and strings

    private mutating func scanComment() -> Bool {
        let start = index
        if let block = grammar.blockComment, matches(block.open, at: index) {
            index += block.open.count
            while index < chars.count, !matches(block.close, at: index) { index += 1 }
            index = min(index + block.close.count, chars.count)
            emit(from: start, .comment)
            return true
        }
        for opener in grammar.lineComments where matches(opener, at: index) {
            if opener.count == 1, let before = unit(at: index - 1), !startsCommentAfter(before) { continue }
            while index < chars.count, chars[index] != Unit.newline { index += 1 }
            emit(from: start, .comment)
            return true
        }
        return false
    }

    private func startsCommentAfter(_ before: UInt16) -> Bool {
        Unit.isSpace(before) || before == Unit.newline || before == Unit.semicolon
            || before == Unit.openParen || before == Unit.pipe || before == Unit.ampersand
    }

    private mutating func scanLifetime() -> Bool {
        guard let first = unit(at: index + 1), Unit.isIdentStart(first) else { return false }
        var end = index + 2
        while end < chars.count, Unit.isIdentPart(chars[end]) { end += 1 }
        if unit(at: end) == Unit.apostrophe { return false }
        let start = index
        index = end
        emit(from: start, .attribute)
        return true
    }

    private mutating func scanString(prefix: Int) -> Bool {
        let opening = index + prefix
        guard let rule = grammar.strings.first(where: { matches($0.delimiter, at: opening) }) else {
            return false
        }
        let start = index
        index = opening + rule.delimiter.count
        while index < chars.count {
            let unit = chars[index]
            if rule.escapes, unit == Unit.backslash {
                index += 2
            } else if matches(rule.delimiter, at: index) {
                if rule.doubling, matches(rule.delimiter, at: index + rule.delimiter.count) {
                    index += rule.delimiter.count * 2
                    continue
                }
                index += rule.delimiter.count
                break
            } else if unit == Unit.newline, !rule.multiline {
                break
            } else {
                index += 1
            }
        }
        index = min(index, chars.count)
        emit(from: start, isKey() ? .property : .string)
        return true
    }

    private func isKey() -> Bool {
        guard has(.keyedStrings) else { return false }
        var position = index
        while let unit = unit(at: position), Unit.isSpace(unit) { position += 1 }
        return unit(at: position) == Unit.colon
    }

    // MARK: Numbers and words

    private mutating func scanNumber() {
        let start = index
        let isHex =
            chars[index] == 48 && [120, 88, 98, 66, 111, 79].contains(unit(at: index + 1) ?? 0)
        var seenDot = chars[index] == Unit.dot
        index += 1
        while index < chars.count {
            let unit = chars[index]
            if isIdentPart(unit) {
                index += 1
                let isExponent = unit == 101 || unit == 69
                if !isHex, isExponent, let sign = self.unit(at: index),
                    sign == Unit.minus || sign == Unit.plus, let digit = self.unit(at: index + 1),
                    Unit.isDigit(digit)
                {
                    index += 1
                }
            } else if unit == Unit.dot, !isHex, !seenDot, let next = self.unit(at: index + 1),
                Unit.isDigit(next)
            {
                seenDot = true
                index += 1
            } else {
                break
            }
        }
        emit(from: start, .number)
    }

    private mutating func scanWord(after previous: String?) {
        let start = index
        index += 1
        while index < chars.count, isIdentPart(chars[index]) { index += 1 }
        let length = index - start
        if has(.stringPrefixes), length <= 2, let next = unit(at: index), Unit.isQuote(next),
            chars[start..<index].allSatisfy({ "rRbBuUfF".utf16.contains($0) })
        {
            index = start
            if scanString(prefix: length) { return }
            index = start + length
        }
        let afterDot = unit(at: start - 1) == Unit.dot && unit(at: start - 2) != Unit.dot
        var key = length <= Self.longestKnownWord ? Unit.text(chars[start..<index]) : nil
        if has(.caseInsensitive) { key = key?.lowercased() }
        let kind =
            has(.shell)
            ? classifyShellWord(key, at: start, after: previous)
            : classifyWord(key, at: start, afterDot: afterDot, after: previous)
        if let kind { emit(from: start, kind) }
        previousWord = key
    }

    private func classifyWord(
        _ key: String?, at start: Int, afterDot: Bool, after previous: String?
    ) -> SyntaxKind? {
        if !afterDot, let key {
            if grammar.keywords.contains(key) { return .keyword }
            if grammar.softKeywords.contains(key), isStatementStart(after: previous), nextStartsOperand() {
                return .keyword
            }
            if let previous {
                if grammar.functionIntroducers.contains(previous) { return .function }
                if grammar.typeIntroducers.contains(previous) { return .type }
            }
            if grammar.constants.contains(key) { return .constant }
            if grammar.types.contains(key) { return .type }
        }
        let capitalized = Unit.isUpper(chars[start])
        if !has(.plainCalls), isCall() {
            return capitalized && has(.capitalizedTypes) ? .type : .function
        }
        if has(.upperConstants), isAllUpper(from: start) { return .constant }
        return capitalized && has(.capitalizedTypes) ? .type : nil
    }

    private func isStatementStart(after previous: String?) -> Bool {
        !lineHasToken || previous.map(Self.statementModifiers.contains) == true
    }

    private func nextStartsOperand() -> Bool {
        var position = index
        while let unit = unit(at: position), Unit.isSpace(unit) { position += 1 }
        guard let next = unit(at: position) else { return false }
        return Unit.isIdentStart(next) || Unit.isDigit(next) || Unit.isQuote(next)
            || next == Unit.openBracket || next == Unit.openBrace || next == Unit.minus
    }

    private func isCall() -> Bool {
        var position = index
        while let unit = unit(at: position), Unit.isSpace(unit) { position += 1 }
        guard let next = unit(at: position) else { return false }
        if next == Unit.openParen { return true }
        guard has(.macros), next == Unit.bang, let open = unit(at: position + 1) else { return false }
        return open == Unit.openParen || open == Unit.openBracket || open == Unit.openBrace
    }

    private func isAllUpper(from start: Int) -> Bool {
        guard index - start >= 2 else { return false }
        return chars[start..<index].allSatisfy {
            Unit.isUpper($0) || Unit.isDigit($0) || $0 == Unit.underscore
        }
    }

    // MARK: Sigils

    private mutating func scanDecorator() -> Bool {
        guard let first = unit(at: index + 1), Unit.isIdentStart(first) else { return false }
        let start = index
        index += 1
        while index < chars.count, Unit.isIdentPart(chars[index]) || chars[index] == Unit.dot { index += 1 }
        emit(from: start, .attribute)
        return true
    }

    private mutating func scanDirective() -> Bool {
        let start = index
        var position = index + 1
        if unit(at: position) == Unit.bang { position += 1 }
        if unit(at: position) == Unit.openBracket {
            var depth = 0
            index = position
            while index < chars.count {
                if chars[index] == Unit.openBracket { depth += 1 }
                if chars[index] == Unit.closeBracket { depth -= 1 }
                index += 1
                if depth == 0 { break }
            }
            emit(from: start, .attribute)
            return true
        }
        guard let first = unit(at: position), Unit.isLetter(first) else { return false }
        while position < chars.count, Unit.isIdentPart(chars[position]) { position += 1 }
        let name = Unit.text(chars[(start + 1)..<position])
        index = position
        emit(from: start, .attribute)
        guard name == "include" || name == "import" else { return true }
        while let unit = unit(at: index), Unit.isSpace(unit) { index += 1 }
        guard unit(at: index) == Unit.lessThan else { return true }
        let header = index
        while index < chars.count, chars[index] != Unit.greaterThan, chars[index] != Unit.newline {
            index += 1
        }
        index = min(index + 1, chars.count)
        emit(from: header, .string)
        return true
    }

    private mutating func scanVariable() -> Bool {
        guard let next = unit(at: index + 1) else { return false }
        let start = index
        if next == Unit.openBrace {
            index += 2
            while index < chars.count, chars[index] != Unit.closeBrace, chars[index] != Unit.newline {
                index += 1
            }
            index = min(index + 1, chars.count)
        } else if Unit.isIdentStart(next) {
            index += 1
            while index < chars.count, Unit.isIdentPart(chars[index]) { index += 1 }
        } else if Unit.isDigit(next) || "@*#?$!-".utf16.contains(next) {
            index += 2
        } else {
            return false
        }
        emit(from: start, .property)
        return true
    }

    // MARK: Shell

    private func isCommandPosition(at start: Int, after previous: String?) -> Bool {
        if let previous, Self.shellCommandWords.contains(previous) { return true }
        var position = start - 1
        while let unit = unit(at: position), Unit.isSpace(unit) { position -= 1 }
        guard let before = unit(at: position) else { return true }
        switch before {
        case Unit.newline, Unit.semicolon, Unit.pipe, Unit.ampersand, Unit.openParen: return true
        case Unit.dollar: return unit(at: position - 1).map { $0 == Unit.newline } ?? true
        default: return false
        }
    }

    private func classifyShellWord(_ key: String?, at start: Int, after previous: String?) -> SyntaxKind? {
        if let key, grammar.keywords.contains(key) { return .keyword }
        guard isCommandPosition(at: start, after: previous) else { return nil }
        return unit(at: index) == Unit.equals ? .property : .function
    }

    private mutating func scanFlag() -> Bool {
        guard let before = unit(at: index - 1), Unit.isSpace(before) || before == Unit.newline,
            let next = unit(at: index + 1), Unit.isLetter(next) || next == Unit.minus
        else { return false }
        let start = index
        while index < chars.count, Unit.isIdentPart(chars[index]) || chars[index] == Unit.minus {
            index += 1
        }
        emit(from: start, .attribute)
        return true
    }

    // MARK: Keys

    private mutating func scanLineKey() -> Bool {
        let isYAML = grammar.lineKeys == .colon
        let separator = isYAML ? Unit.colon : Unit.equals
        var start = index
        if isYAML {
            while unit(at: start) == Unit.minus, let next = unit(at: start + 1), Unit.isSpace(next) {
                start += 2
                while let unit = unit(at: start), Unit.isSpace(unit) { start += 1 }
            }
        } else if unit(at: start) == Unit.openBracket {
            while index < chars.count, chars[index] != Unit.newline { index += 1 }
            emit(from: start, .type)
            return true
        }
        var end = start
        if let quote = unit(at: start), Unit.isQuote(quote) {
            end += 1
            while let unit = unit(at: end), unit != quote, unit != Unit.newline { end += 1 }
            end += 1
        } else {
            while let unit = unit(at: end), unit != separator, unit != Unit.newline, unit != Unit.hash {
                end += 1
            }
        }
        end = min(end, chars.count)
        while end > start, let unit = unit(at: end - 1), Unit.isSpace(unit) { end -= 1 }
        var colon = end
        while let unit = unit(at: colon), Unit.isSpace(unit) { colon += 1 }
        guard end > start, unit(at: colon) == separator else { return false }
        if isYAML, let after = unit(at: colon + 1), !Unit.isSpace(after), after != Unit.newline {
            return false
        }
        emit(from: start, to: end, .property)
        index = colon + 1
        return true
    }
}
