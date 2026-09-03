import Foundation

/// The launcher's two orderings, kept pure so a harness ranks the shipped code and not a mirror.
enum LauncherOrder {
    /// A typed query: match quality plus what the user has taught, strongest first.
    static func ranked<Item>(
        _ items: [Item], query: FuzzyMatch.Query, limit: Int,
        fields: (Item) -> SearchFields, usage: (Item) -> Int, name: (Item) -> String
    ) -> [Item] {
        let scored = items.enumerated().compactMap { position, item -> (Item, Int, Int)? in
            guard let quality = SearchRelevance.quality(query, fields: fields(item)) else {
                return nil
            }
            return (item, quality + usage(item), position)
        }
        return
            scored
            .sorted { precedes($0, $1, name: name) }
            .prefix(limit)
            .map(\.0)
    }

    /// The empty query, ordered inside each run: moving one would desync selection from the rows.
    static func within<Item, Group: Equatable>(
        _ items: [Item], group: (Item) -> Group, usage: (Item) -> Int, name: (Item) -> String
    ) -> [Item] {
        var result: [Item] = []
        result.reserveCapacity(items.count)
        var run: [(Item, Int, Int)] = []
        var current: Group?
        for (position, item) in items.enumerated() {
            let itemGroup = group(item)
            if let current, current != itemGroup {
                result.append(contentsOf: run.sorted { precedes($0, $1, name: name) }.map(\.0))
                run.removeAll(keepingCapacity: true)
            }
            current = itemGroup
            run.append((item, usage(item), position))
        }
        result.append(contentsOf: run.sorted { precedes($0, $1, name: name) }.map(\.0))
        return result
    }

    /// Score, then the user's own alphabet, then publication order — a total order either way.
    private static func precedes<Item>(
        _ lhs: (Item, Int, Int), _ rhs: (Item, Int, Int), name: (Item) -> String
    ) -> Bool {
        if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
        let order = name(lhs.0).localizedCaseInsensitiveCompare(name(rhs.0))
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.2 < rhs.2
    }
}
