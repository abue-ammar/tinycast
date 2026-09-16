import Foundation

struct NoteTask: Sendable {
    let markerRange: NSRange
    let stateRange: NSRange
    let contentRange: NSRange
    let continuation: String
    let isChecked: Bool

    static func parse(_ source: String) -> [NoteTask] {
        let text = source as NSString
        var tasks: [NoteTask] = []
        var offset = 0
        var fence: (character: Character, count: Int)?
        while offset < text.length {
            let lineRange = text.lineRange(for: NSRange(location: offset, length: 0))
            let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if let character = trimmed.first, character == "`" || character == "~" {
                let count = trimmed.prefix(while: { $0 == character }).count
                if let active = fence {
                    if character == active.character, count >= active.count,
                        trimmed.dropFirst(count).allSatisfy({ $0.isWhitespace }) {
                        fence = nil
                    }
                } else if count >= 3 {
                    fence = (character, count)
                }
            } else if fence == nil, let task = parseLine(line, offset: offset) {
                tasks.append(task)
            }
            offset = NSMaxRange(lineRange)
        }
        return tasks
    }

    private static func parseLine(_ line: String, offset: Int) -> NoteTask? {
        let indentation = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let body = String(line.dropFirst(indentation.count))
        let prefixes = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] ",
                        "+ [ ] ", "+ [x] ", "+ [X] "]
        guard let prefix = prefixes.first(where: { body.hasPrefix($0) }) else { return nil }
        let start = offset + (indentation as NSString).length
        let bracket = (prefix as NSString).range(of: "[").location
        let length = (prefix as NSString).length
        return NoteTask(
            markerRange: NSRange(location: start, length: length - 1),
            stateRange: NSRange(location: start + bracket + 1, length: 1),
            contentRange: NSRange(location: start + length, length: (body as NSString).length - length),
            continuation: indentation + "- [ ] ",
            isChecked: prefix.lowercased().contains("x"))
    }
}
