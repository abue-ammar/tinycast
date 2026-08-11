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
        guard !query.isEmpty else {
            return NoteSearchResult(summary: summary, score: 0, excerpt: nil)
        }

        var titleScore = 0
        var titleMatches = 0
        var firstBodyRange: Range<String.Index>?
        for term in query.terms {
            if let match = FuzzyMatch.match(query: term, candidate: summary.title) {
                titleMatches += 1
                titleScore += match.score
                continue
            }
            guard let source,
                let range = source.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive])
            else { return nil }
            if firstBodyRange == nil { firstBodyRange = range }
        }

        let band: Int
        if titleMatches == query.terms.count {
            band = 2_000_000
        } else if titleMatches > 0 {
            band = 1_000_000
        } else {
            band = 0
        }
        return NoteSearchResult(
            summary: summary,
            score: band + titleScore,
            excerpt: firstBodyRange.flatMap { range in source.map { excerpt(in: $0, around: range) } })
    }

    static func precedes(_ lhs: NoteSearchResult, _ rhs: NoteSearchResult) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.summary.modifiedAt != rhs.summary.modifiedAt {
            return lhs.summary.modifiedAt > rhs.summary.modifiedAt
        }
        return lhs.summary.title.localizedCaseInsensitiveCompare(rhs.summary.title)
            == .orderedAscending
    }

    private static func excerpt(in source: String, around range: Range<String.Index>) -> String {
        let radius = 70
        let lower = source.index(range.lowerBound, offsetBy: -radius, limitedBy: source.startIndex)
            ?? source.startIndex
        let upper = source.index(range.upperBound, offsetBy: radius, limitedBy: source.endIndex)
            ?? source.endIndex
        var value = String(source[lower..<upper])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        while value.contains("  ") {
            value = value.replacingOccurrences(of: "  ", with: " ")
        }
        value = value.trimmingCharacters(in: .whitespaces)
        if lower != source.startIndex { value = "…" + value }
        if upper != source.endIndex { value += "…" }
        return value
    }
}
