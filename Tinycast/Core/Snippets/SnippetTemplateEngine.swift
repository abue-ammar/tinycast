import Foundation

enum SnippetTemplateEngine {
    struct ExpansionContext: Sendable {
        let clipboard: String
        let selection: String
        let now: Date
        let calendar: Calendar
        let locale: Locale
        let timeZone: TimeZone

        init(
            clipboard: String,
            selection: String,
            now: Date,
            calendar: Calendar,
            locale: Locale,
            timeZone: TimeZone
        ) {
            var calendar = calendar
            calendar.timeZone = timeZone
            self.clipboard = clipboard
            self.selection = selection
            self.now = now
            self.calendar = calendar
            self.locale = locale
            self.timeZone = timeZone
        }
    }

    struct ExpansionResult: Sendable, Equatable {
        let text: String
        let cursorOffsetFromEnd: Int?
        let missingArguments: [String]
    }

    private static let maximumReferenceDepth = 5
    private static let comparisonLocale = Locale(identifier: "en_US_POSIX")

    static func expand(
        _ record: StoredSnippet,
        snippets: [StoredSnippet],
        context: ExpansionContext,
        userArguments: [String: String] = [:]
    ) -> ExpansionResult {
        let orderedSnippets = snippets.sorted { $0.id < $1.id }
        let expansion = expandRecord(
            record,
            snippets: orderedSnippets,
            context: context,
            userArguments: userArguments,
            depth: 0,
            visitedIDs: [record.id]
        )
        let cursorOffset = expansion.cursorCharacterOffset.map { expansion.text.count - $0 }
        return ExpansionResult(
            text: expansion.text,
            cursorOffsetFromEnd: cursorOffset,
            missingArguments: expansion.missingArguments
        )
    }

    private struct Expansion {
        var text = ""
        var cursorCharacterOffset: Int?
        var missingArguments: [String] = []
        var missingArgumentSet = Set<String>()

        mutating func append(_ value: String) {
            text += value
        }

        mutating func append(_ nested: Expansion) {
            let insertionOffset = text.count
            if cursorCharacterOffset == nil, let nestedCursor = nested.cursorCharacterOffset {
                cursorCharacterOffset = insertionOffset + nestedCursor
            }
            text += nested.text
            for argument in nested.missingArguments {
                addMissingArgument(argument)
            }
        }

        mutating func markCursor() {
            if cursorCharacterOffset == nil {
                cursorCharacterOffset = text.count
            }
        }

        mutating func addMissingArgument(_ argument: String) {
            if missingArgumentSet.insert(argument).inserted {
                missingArguments.append(argument)
            }
        }
    }

    private enum Segment {
        case literal(String)
        case clipboard
        case selection
        case date
        case time
        case formattedDate(String)
        case argument(name: String, source: String)
        case cursor
        case snippetReference(key: String, source: String)
    }

    private static func expandRecord(
        _ record: StoredSnippet,
        snippets: [StoredSnippet],
        context: ExpansionContext,
        userArguments: [String: String],
        depth: Int,
        visitedIDs: Set<StoredSnippet.ID>
    ) -> Expansion {
        var result = Expansion()
        for segment in parseSegments(record.snippet.text) {
            switch segment {
            case .literal(let value):
                result.append(value)
            case .clipboard:
                result.append(context.clipboard)
            case .selection:
                result.append(context.selection)
            case .date:
                result.append(formatDate(context.now, dateStyle: .medium, timeStyle: .none, context: context))
            case .time:
                result.append(formatDate(context.now, dateStyle: .none, timeStyle: .short, context: context))
            case .formattedDate(let format):
                result.append(formatDate(context.now, format: format, context: context))
            case .argument(let name, let source):
                if let value = userArguments[name] {
                    result.append(value)
                } else {
                    result.append(source)
                    result.addMissingArgument(name)
                }
            case .cursor:
                result.markCursor()
            case .snippetReference(let key, let source):
                guard depth < maximumReferenceDepth,
                    let target = resolveReference(key, snippets: snippets),
                    !visitedIDs.contains(target.id)
                else {
                    result.append(source)
                    continue
                }
                var nestedVisited = visitedIDs
                nestedVisited.insert(target.id)
                result.append(expandRecord(
                    target,
                    snippets: snippets,
                    context: context,
                    userArguments: userArguments,
                    depth: depth + 1,
                    visitedIDs: nestedVisited
                ))
            }
        }
        return result
    }

    private static func parseSegments(_ source: String) -> [Segment] {
        var segments: [Segment] = []
        var position = source.startIndex

        while position < source.endIndex,
            let opening = source[position...].firstIndex(of: "{")
        {
            if position < opening {
                segments.append(.literal(String(source[position..<opening])))
            }
            guard let closing = source[source.index(after: opening)...].firstIndex(of: "}") else {
                segments.append(.literal(String(source[opening...])))
                return segments
            }

            let end = source.index(after: closing)
            let rawToken = String(source[opening..<end])
            let tokenBody = String(source[source.index(after: opening)..<closing])
            if let segment = segment(for: tokenBody, source: rawToken) {
                segments.append(segment)
                position = end
            } else {
                segments.append(.literal("{"))
                position = source.index(after: opening)
            }
        }

        if position < source.endIndex {
            segments.append(.literal(String(source[position...])))
        }
        return segments
    }

    private static func segment(for body: String, source: String) -> Segment? {
        switch body {
        case "clipboard": return .clipboard
        case "selection": return .selection
        case "date": return .date
        case "time": return .time
        case "argument": return .argument(name: "Argument", source: source)
        case "cursor": return .cursor
        default: break
        }

        if body.hasPrefix("snippet:") {
            let key = body.dropFirst("snippet:".count).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            return .snippetReference(key: key, source: source)
        }
        if let name = quotedAttribute(in: body, command: "argument", attribute: "name"), !name.isEmpty {
            return .argument(name: name, source: source)
        }
        if let format = quotedAttribute(in: body, command: "date", attribute: "format"), !format.isEmpty {
            return .formattedDate(format)
        }
        return nil
    }

    private static func quotedAttribute(in body: String, command: String, attribute: String) -> String? {
        guard body.hasPrefix(command) else { return nil }
        var remainder = body.dropFirst(command.count)
        guard remainder.first?.isWhitespace == true else { return nil }
        remainder = remainder.drop(while: \Character.isWhitespace)
        guard remainder.hasPrefix(attribute) else { return nil }
        remainder = remainder.dropFirst(attribute.count)
        remainder = remainder.drop(while: \Character.isWhitespace)
        guard remainder.first == "=" else { return nil }
        remainder = remainder.dropFirst()
        remainder = remainder.drop(while: \Character.isWhitespace)
        guard remainder.first == "\"" else { return nil }
        remainder = remainder.dropFirst()

        var decoded = ""
        var escaped = false
        while let character = remainder.first {
            remainder = remainder.dropFirst()
            if escaped {
                switch character {
                case "\\": decoded.append("\\")
                case "\"": decoded.append("\"")
                case "n": decoded.append("\n")
                case "r": decoded.append("\r")
                case "t": decoded.append("\t")
                default: return nil
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return remainder.allSatisfy(\Character.isWhitespace) ? decoded : nil
            } else {
                decoded.append(character)
            }
        }
        return nil
    }

    private static func resolveReference(
        _ key: String,
        snippets: [StoredSnippet]
    ) -> StoredSnippet? {
        let normalizedKey = normalizeReference(key)
        if let nameMatch = snippets.first(where: {
            normalizeReference($0.snippet.name) == normalizedKey
        }) {
            return nameMatch
        }
        return snippets.first(where: {
            guard let keyword = $0.snippet.keyword else { return false }
            return normalizeReference(keyword) == normalizedKey
        })
    }

    private static func normalizeReference(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: comparisonLocale)
    }

    private static func formatDate(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        context: ExpansionContext
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = context.calendar
        formatter.locale = context.locale
        formatter.timeZone = context.timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private static func formatDate(
        _ date: Date,
        format: String,
        context: ExpansionContext
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = context.calendar
        formatter.locale = context.locale
        formatter.timeZone = context.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
