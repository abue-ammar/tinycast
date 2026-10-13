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
        return (droppingDanglingFence(prose), Array(choices.prefix(maxCount)))
    }

    /// The on-device model's form: a `choices` line, then list items to the end, fenced or not.
    private static func labelled(_ text: String) -> (text: String, choices: [String])? {
        guard mentionsChoices(text) else { return nil }
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, isBlank(last) || isBareFence(last) { lines.removeLast() }
        guard let label = lines.lastIndex(where: isLabel), label < lines.count - 1 else { return nil }
        let items = lines[(label + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty, items.allSatisfy(isListItem) else { return nil }
        let choices = items.map(option).filter { !$0.isEmpty && $0.count <= maxLength }
        guard !choices.isEmpty else { return nil }
        var before = Array(lines[..<label])
        while let last = before.last, isBlank(last) { before.removeLast() }
        if let open = openFence(in: before) {
            guard open.isBare, open.line == before.count - 1 else { return nil }
            before.removeLast()
        }
        let prose = before.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (prose, Array(choices.prefix(maxCount)))
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isBareFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "```"
    }

    private static func openFence(in lines: [String]) -> (line: Int, run: Int, isBare: Bool)? {
        var open: (line: Int, run: Int, isBare: Bool)?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let run = trimmed.prefix { $0 == "`" }.count
            guard run >= 3 else { continue }
            let isBare = trimmed.count == run
            if let current = open {
                if isBare, run >= current.run { open = nil }
            } else {
                open = (index, run, isBare)
            }
        }
        return open
    }

    private static func droppingDanglingFence(_ prose: String) -> String {
        var lines = prose.components(separatedBy: "\n")
        guard let open = openFence(in: lines), open.line == lines.count - 1 else { return prose }
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `choices`, as a model might dress it: bold, a heading, a trailing colon.
    private static func isLabel(_ line: String) -> Bool {
        guard mentionsChoices(line) else { return false }
        return line.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: #/(?i)(?:#{1,6}\s*)?(?:\*\*|__)?choices:?(?:\*\*|__)?:?/#) != nil
    }

    private static func mentionsChoices(_ text: String) -> Bool {
        text.range(of: "choices", options: .caseInsensitive) != nil
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
