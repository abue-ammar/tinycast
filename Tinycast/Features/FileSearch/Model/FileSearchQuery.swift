import Foundation

enum FileSearchQuery {
    static let candidateLimit = 1_000
    static let resultLimit = 200

    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \Character.isWhitespace).map(String.init)
    }

    static func expression(for query: String, excluding exclusions: [String] = []) -> String? {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return nil }
        let matches = terms.map { "kMDItemFSName == \"*\(escape($0))*\"cd" }
        // Excluding in the predicate keeps ignored files from consuming the candidate cap.
        let excludes = exclusions.map { "kMDItemFSName != \"\(escapeGlob($0))\"cd" }
        return (matches + excludes).joined(separator: " && ")
    }

    static func rank(
        _ results: [FileSearchResult], for query: String, ignoring ignore: FileSearchIgnoreList
    ) -> [FileSearchResult] {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return [] }
        return results.filter { !isExcludedPath($0.id, ignoring: ignore) }.map { result in
            let full = FuzzyMatch.score(query: query, candidate: result.name)
            let termScore = terms.compactMap { FuzzyMatch.score(query: $0, candidate: result.name) }
                .reduce(0, +)
            return (result, full, termScore)
        }
        .sorted { left, right in
            switch (left.1, right.1) {
            case let (leftScore?, rightScore?) where leftScore != rightScore:
                return leftScore > rightScore
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if left.2 != right.2 { return left.2 > right.2 }
                let nameOrder = left.0.name.localizedCaseInsensitiveCompare(right.0.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return left.0.id.localizedCaseInsensitiveCompare(right.0.id) == .orderedAscending
            }
        }
        .prefix(resultLimit)
        .map(\.0)
    }

    static func matches(filename: String, query: String) -> Bool {
        terms(in: query).allSatisfy { term in
            filename.range(
                of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Hidden paths and bundle contents are structural: they are what keeps File Search permission-free.
    static func isExcludedPath(_ path: String, ignoring ignore: FileSearchIgnoreList) -> Bool {
        let structural = path.split(separator: "/").contains { component in
            (component.hasPrefix(".") && component != "." && component != "..")
                || component.lowercased().hasSuffix(".app")
        }
        return structural || ignore.excludes(path: path)
    }

    /// A typed term is literal, so its wildcards are neutralized along with the string delimiters.
    private static func escape(_ term: String) -> String {
        quoting(term, escaping: ["\\", "\"", "*", "?"])
    }

    /// A user pattern keeps its `*`, since that is the one wildcard Spotlight evaluates.
    private static func escapeGlob(_ pattern: String) -> String {
        quoting(pattern, escaping: ["\\", "\""])
    }

    private static func quoting(_ text: String, escaping characters: Set<Character>) -> String {
        var escaped = ""
        for character in text {
            if characters.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
