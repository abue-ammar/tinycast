import Foundation

enum FileSearchQuery {
    static let candidateLimit = 1_000
    static let resultLimit = 200
    static let excludedDirectoryNames = [
        "node_modules", "DerivedData", "build", "dist", "target", "Pods"
    ]
    private static let excludedDirectoryNamesFolded = Set(
        excludedDirectoryNames.map { $0.lowercased() })

    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \Character.isWhitespace).map(String.init)
    }

    static func expression(for query: String) -> String? {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return nil }
        return terms.map { term in
            "kMDItemFSName == \"*\(escape(term))*\"cd"
        }
        .joined(separator: " && ")
    }

    static func rank(_ results: [FileSearchResult], for query: String) -> [FileSearchResult] {
        let terms = terms(in: query)
        guard !terms.isEmpty else { return [] }
        return results.filter { !isExcludedPath($0.id) }.map { result in
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

    static func isExcludedPath(_ path: String) -> Bool {
        return URL(fileURLWithPath: path).pathComponents.contains { component in
            let folded = component.lowercased()
            return (component.hasPrefix(".") && component != "." && component != "..")
                || excludedDirectoryNamesFolded.contains(folded)
                || folded.hasSuffix(".app")
        }
    }

    private static func escape(_ term: String) -> String {
        var escaped = ""
        for character in term {
            if character == "\\" || character == "\"" || character == "*" || character == "?" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
