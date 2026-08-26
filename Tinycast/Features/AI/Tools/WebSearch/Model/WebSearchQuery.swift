import Foundation

public struct WebSearchQuery: Equatable, Sendable {
    public let rawQuery: String
    public let searchTerm: String
    public let category: WebSearchCategory
    public let siteConstraint: String?

    public var siteFilter: String? { siteConstraint }

    public init(query: String, category: WebSearchCategory = .general) {
        self.rawQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedCategory = category
        let text = self.rawQuery
        var site: String?

        var words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Check for bangs anywhere in the words
        if let bangIndex = words.firstIndex(where: { $0.hasPrefix("!") }) {
            let bang = String(words[bangIndex].dropFirst()).lowercased()
            var matched = false
            switch bang {
            case "w", "wiki", "wikipedia":
                parsedCategory = .wikipedia
                matched = true
            case "n", "news":
                parsedCategory = .news
                matched = true
            default:
                break
            }
            if matched {
                words.remove(at: bangIndex)
            }
        } else if parsedCategory == .general {
            let lower = text.lowercased()
            if lower.contains("news") || lower.contains("today") || lower.contains("latest") || lower.contains("breaking") {
                parsedCategory = .news
            }
        }

        // Clean out hallucinated past years from news queries
        if parsedCategory == .news {
            words = words.filter { $0 != "2024" && $0 != "2025" }
        }

        // Check for site: filter
        if let siteIndex = words.firstIndex(where: { $0.lowercased().hasPrefix("site:") }) {
            let token = words[siteIndex]
            site = String(token.dropFirst(5))
        }

        self.category = parsedCategory
        self.siteConstraint = site
        self.searchTerm = words.joined(separator: " ")
    }
}
