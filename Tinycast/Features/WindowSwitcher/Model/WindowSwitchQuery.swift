import Foundation

enum WindowSwitchQuery {
    static let resultLimit = 200

    /// Ties break on the incoming position, so equally good matches keep the recency order.
    static func rank(_ entries: [WindowSwitchEntry], for query: String) -> [WindowSwitchEntry] {
        let folded = FuzzyMatch.Query(query)
        guard !folded.isEmpty else { return Array(entries.prefix(resultLimit)) }
        return entries.enumerated()
            .compactMap { position, entry -> (WindowSwitchEntry, Int, Int)? in
                guard let quality = SearchRelevance.quality(folded, fields: entry.searchFields())
                else { return nil }
                return (entry, quality, position)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .prefix(resultLimit)
            .map(\.0)
    }
}
