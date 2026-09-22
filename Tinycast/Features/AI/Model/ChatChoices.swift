import Foundation

/// A reply may end with a ```choices fence; its lines become buttons that answer for the reader.
enum ChatChoices {
    static let maxCount = 6
    /// Past this a line is prose that wandered into the fence, not an option.
    static let maxLength = 160

    /// The prose around the fence, and its options; an unclosed fence is still hidden mid-stream.
    static func split(_ text: String) -> (text: String, choices: [String]) {
        guard let open = text.range(of: "```choices", options: .backwards),
            open.lowerBound == text.startIndex || text[text.index(before: open.lowerBound)] == "\n"
        else { return labelled(text) ?? (text, []) }
        let body = text[open.upperBound...]
        let close = body.range(of: "```")
        let fenced = close.map { body[..<$0.lowerBound] } ?? body
        let after = close.map { String(body[$0.upperBound...]) } ?? ""
        let choices = fenced.split(whereSeparator: \.isNewline)
            .map { option(String($0)) }
            .filter { !$0.isEmpty && $0.count <= maxLength }
        let prose = [String(text[..<open.lowerBound]), after]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return (prose, Array(choices.prefix(maxCount)))
    }

    /// The on-device model's fenceless form: a lone `choices` line, then only list items to the end.
    private static func labelled(_ text: String) -> (text: String, choices: [String])? {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        guard let label = lines.lastIndex(where: isLabel), label < lines.count - 1 else { return nil }
        let items = lines[(label + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty, items.allSatisfy(isListItem) else { return nil }
        let choices = items.map(option).filter { !$0.isEmpty && $0.count <= maxLength }
        guard !choices.isEmpty else { return nil }
        let prose = lines[..<label].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (prose, Array(choices.prefix(maxCount)))
    }

    /// `choices`, as a model might dress it: bold, a heading, a trailing colon.
    private static func isLabel(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: #/(?i)(?:#{1,6}\s*)?(?:\*\*|__)?choices:?(?:\*\*|__)?:?/#) != nil
    }

    private static func isListItem(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).firstMatch(of: #/^(?:[-*•]|\d+[.)])\s+\S/#) != nil
    }

    /// A model lists options the way it lists anything, so a bullet or a number is not the option.
    private static func option(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if let marker = trimmed.firstMatch(of: #/^(?:[-*•]|\d+[.)])\s+/#) {
            trimmed.removeSubrange(marker.range)
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }
}
