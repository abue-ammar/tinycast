import Foundation

enum NoteSearch {
    struct Query: Sendable {
        let terms: [String]

        init(_ raw: String) {
            terms = raw.split(whereSeparator: \Character.isWhitespace).map(String.init)
        }

        var isEmpty: Bool { terms.isEmpty }
    }

    static func match(
        query: Query,
        summary: NoteSummary,
        source: String?
    ) -> NoteSearchResult? {
        guard !query.isEmpty else { return nil }

        var titleScore = 0
        var titleMatches = 0
        for term in query.terms {
            if let match = FuzzyMatch.match(query: term, candidate: summary.displayTitle) {
                titleMatches += 1
                titleScore += match.score
                continue
            }
            guard let source,
                source.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive]) != nil
            else { return nil }
        }

        let band: Int
        if titleMatches == query.terms.count {
            band = 2_000_000
        } else if titleMatches > 0 {
            band = 1_000_000
        } else {
            band = 0
        }
        return NoteSearchResult(summary: summary, score: band + titleScore)
    }

    static func precedes(_ lhs: NoteSearchResult, _ rhs: NoteSearchResult) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.summary.modifiedAt != rhs.summary.modifiedAt {
            return lhs.summary.modifiedAt > rhs.summary.modifiedAt
        }
        return lhs.summary.displayTitle.localizedCaseInsensitiveCompare(rhs.summary.displayTitle)
            == .orderedAscending
    }
}
