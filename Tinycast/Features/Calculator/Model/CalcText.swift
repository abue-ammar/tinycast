import Foundation

enum CalcText {
    static func evaluate(_ query: String) -> CalcResult? {
        guard let open = query.firstIndex(where: isQuote), let close = query.lastIndex(where: isQuote),
            open < close
        else { return nil }
        let text = String(query[query.index(after: open)..<close])
        let before = query[..<open].lowercased().split(whereSeparator: \.isBlank)
        let after = query[query.index(after: close)...].lowercased().split(whereSeparator: \.isBlank)
        var words = before.map(String.init)
        if words.last == "of" || words.last == "in" { words.removeLast() }
        if words.isEmpty, let connector = after.first, ["to", "in", "as"].contains(connector) {
            words = after.dropFirst().map(String.init)
        } else if !after.isEmpty {
            return nil
        }
        guard let answer = apply(words, to: text) else { return nil }
        switch answer {
        case .count(let count, let badge):
            return CalcResult(
                expression: query, sourceBadge: String(localized: "Text"), targetBadge: badge,
                payload: .number(Double(count)))
        case .text(let output):
            guard !output.isEmpty else { return nil }
            return CalcResult(
                expression: query, sourceBadge: String(localized: "Text"),
                targetBadge: String(localized: "Result"), payload: .value(display: output, copyText: output),
                canChain: false)
        }
    }

    private enum Answer {
        case count(Int, badge: String)
        case text(String)
    }

    private static func isQuote(_ char: Character) -> Bool {
        char == "\"" || char == "“" || char == "”"
    }

    private static let characterWords: Set<String> = ["characters", "character", "chars", "char", "letters"]
    private static let wordWords: Set<String> = ["words", "word"]

    private static func apply(_ words: [String], to text: String) -> Answer? {
        switch words.joined(separator: " ") {
        case "length", "len", "count", "character count", "characters", "chars", "letters",
            "count characters":
            return .count(text.count, badge: String(localized: "Characters"))
        case "word count", "words", "count words":
            return .count(text.split(whereSeparator: \.isBlank).count, badge: String(localized: "Words"))
        case "uppercase", "upper case", "upper", "caps": return .text(text.uppercased())
        case "lowercase", "lower case", "lower": return .text(text.lowercased())
        case "capitalize", "capitalized", "title case": return .text(text.capitalized)
        case "reverse", "reversed": return .text(String(text.reversed()))
        case "trim", "trimmed": return .text(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: break
        }
        guard words.count == 3, words[0] == "first" || words[0] == "last", let count = Int(words[1]),
            count >= 0
        else { return nil }
        let first = words[0] == "first"
        if characterWords.contains(words[2]) {
            return .text(String(first ? text.prefix(count) : text.suffix(count)))
        }
        guard wordWords.contains(words[2]) else { return nil }
        let split = text.split(whereSeparator: \.isBlank)
        return .text((first ? split.prefix(count) : split.suffix(count)).joined(separator: " "))
    }
}
