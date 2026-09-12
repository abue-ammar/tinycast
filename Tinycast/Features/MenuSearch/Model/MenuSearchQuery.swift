import Foundation

enum MenuSearchQuery {
    static let resultLimit = 200

    static func rank(_ items: [MenuSearchItem], for query: String) -> [MenuSearchItem] {
        let whole = FuzzyMatch.Query(query)
        guard !whole.isEmpty else { return [] }
        let terms = query.split(whereSeparator: \Character.isWhitespace).map(String.init)
            .map(FuzzyMatch.Query.init)
        return items.compactMap { item -> (MenuSearchItem, Int?, Int)? in
            let quality = SearchRelevance.quality(whole, fields: item.searchFields())
            let termScore = terms.compactMap { FuzzyMatch.score($0, candidate: item.title) }
                .reduce(0, +)
            guard quality != nil || termScore > 0 else { return nil }
            return (item, quality, termScore)
        }
        .sorted { left, right in
            switch (left.1, right.1) {
            case let (leftQuality?, rightQuality?) where leftQuality != rightQuality:
                return leftQuality > rightQuality
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if left.2 != right.2 { return left.2 > right.2 }
                if left.0.displayPath != right.0.displayPath {
                    return
                        left.0.displayPath.localizedCaseInsensitiveCompare(right.0.displayPath)
                        == .orderedAscending
                }
                return
                    left.0.title.localizedCaseInsensitiveCompare(right.0.title)
                    == .orderedAscending
            }
        }
        .prefix(resultLimit)
        .map(\.0)
    }
}
