import AppKit
import Foundation

@MainActor
enum SnippetTemplateEngine {
    struct ExpansionResult {
        let text: String
        let cursorOffsetFromEnd: Int?
        let missingArguments: [String]

        init(text: String, cursorOffsetFromEnd: Int?, missingArguments: [String] = []) {
            self.text = text
            self.cursorOffsetFromEnd = cursorOffsetFromEnd
            self.missingArguments = missingArguments
        }
    }

    /// Expands all variables, references to other snippets, clipboard/selection, date/time and cursor markers.
    static func expand(
        _ snippet: Snippet,
        snippets: [Snippet],
        userArguments: [String: String] = [:],
        depth: Int = 0,
        visitedIDs: Set<UUID> = []
    ) -> ExpansionResult {
        // Prevent infinite recursive loops
        guard depth < 5, !visitedIDs.contains(snippet.id) else {
            return ExpansionResult(text: snippet.text, cursorOffsetFromEnd: nil)
        }

        var currentVisited = visitedIDs
        currentVisited.insert(snippet.id)

        var content = snippet.text

        // 1. Expand nested snippets: {snippet:Snippet Name} or {snippet:keyword} or {snippet:id}
        content = expandSnippetReferences(
            content,
            snippets: snippets,
            userArguments: userArguments,
            depth: depth,
            visitedIDs: currentVisited
        )

        // 2. Expand {clipboard}
        if content.contains("{clipboard}") {
            let pbString = NSPasteboard.general.string(forType: .string) ?? ""
            content = content.replacingOccurrences(of: "{clipboard}", with: pbString)
        }

        // 3. Expand {selection}
        if content.contains("{selection}") {
            let selectedText = getActiveSelectionText() ?? ""
            content = content.replacingOccurrences(of: "{selection}", with: selectedText)
        }

        // 4. Expand {date} / {time} / {date format="..."}
        content = expandDateAndFormatter(content)

        // 5. Expand {argument} or {argument name="..."}
        var missingArgs: [String] = []
        content = expandArguments(content, userArguments: userArguments, missingArgs: &missingArgs)

        // 6. Handle {cursor}
        var offsetFromEnd: Int? = nil
        if let cursorRange = content.range(of: "{cursor}") {
            let afterCursor = content[cursorRange.upperBound...]
            offsetFromEnd = afterCursor.count
            content.removeSubrange(cursorRange)
        }

        return ExpansionResult(
            text: content,
            cursorOffsetFromEnd: offsetFromEnd,
            missingArguments: missingArgs
        )
    }

    private static func expandSnippetReferences(
        _ text: String,
        snippets: [Snippet],
        userArguments: [String: String],
        depth: Int,
        visitedIDs: Set<UUID>
    ) -> String {
        let pattern = #"\{snippet:([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        var result = text
        // Process in reverse to maintain correct replacement ranges
        for match in matches.reversed() {
            let refKey = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let fullMatchRange = Range(match.range, in: result)!

            // Find matching snippet by name, keyword, or UUID
            if let targetSnippet = snippets.first(where: {
                $0.name.caseInsensitiveCompare(refKey) == .orderedSame ||
                $0.keyword == refKey ||
                $0.id.uuidString == refKey
            }) {
                let subResult = expand(
                    targetSnippet,
                    snippets: snippets,
                    userArguments: userArguments,
                    depth: depth + 1,
                    visitedIDs: visitedIDs
                )
                result.replaceSubrange(fullMatchRange, with: subResult.text)
            } else {
                result.replaceSubrange(fullMatchRange, with: "")
            }
        }
        return result
    }

    private static func expandDateAndFormatter(_ text: String) -> String {
        var result = text

        // Handle {date format="..."}
        let customFormatPattern = #"\{date\s+format="([^"]+)"\}"#
        if let regex = try? NSRegularExpression(pattern: customFormatPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let formatStr = nsString.substring(with: match.range(at: 1))
                let formatter = DateFormatter()
                formatter.dateFormat = formatStr
                let dateStr = formatter.string(from: Date())
                let range = Range(match.range, in: result)!
                result.replaceSubrange(range, with: dateStr)
            }
        }

        // Standard {date}
        if result.contains("{date}") {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            result = result.replacingOccurrences(of: "{date}", with: formatter.string(from: Date()))
        }

        // Standard {time}
        if result.contains("{time}") {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            result = result.replacingOccurrences(of: "{time}", with: formatter.string(from: Date()))
        }

        return result
    }

    private static func expandArguments(
        _ text: String,
        userArguments: [String: String],
        missingArgs: inout [String]
    ) -> String {
        var result = text

        // Match {argument name="..."}
        let namedPattern = #"\{argument\s+name="([^"]+)"\}"#
        if let regex = try? NSRegularExpression(pattern: namedPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let argName = nsString.substring(with: match.range(at: 1))
                let range = Range(match.range, in: result)!
                if let val = userArguments[argName] {
                    result.replaceSubrange(range, with: val)
                } else {
                    if !missingArgs.contains(argName) {
                        missingArgs.append(argName)
                    }
                }
            }
        }

        // Match plain {argument}
        if result.contains("{argument}") {
            let argName = "Argument"
            if let val = userArguments[argName] {
                result = result.replacingOccurrences(of: "{argument}", with: val)
            } else {
                if !missingArgs.contains(argName) {
                    missingArgs.append(argName)
                }
            }
        }

        return result
    }

    private static func getActiveSelectionText() -> String? {
        return nil
    }
}
