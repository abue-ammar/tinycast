import Foundation

/// What the user reaches for, offered while the search field is empty.
enum LauncherSuggestions {
    static let limit = 5
    /// A just-installed app is offered before it has ever been opened.
    static let recentInstallLimit = 2
    static let recentInstallWindow: TimeInterval = 5 * 60

    struct Traits: Sendable {
        var signals: LauncherOrder.Signals
        var installedAt: Date?
        /// A bound shortcut is already a faster way in than this section.
        var hasHotKey: Bool
        /// A built-in command worth offering someone with no history yet; higher first.
        var priority: Int?
    }

    /// `items` holds only what may be suggested: no favorites, meetings or Tinycast itself.
    static func select<Item>(from items: [Item], now: Date, traits: (Item) -> Traits) -> [Item] {
        let all = items.map(traits)
        let signals: (Int) -> LauncherOrder.Signals = { all[$0].signals }
        let fresh = LauncherOrder.byUsage(
            all.indices.filter { isFreshInstall(all[$0], now: now) }, signals: signals
        ).prefix(recentInstallLimit)
        var taken = Set(fresh)
        let used = LauncherOrder.byUsage(
            all.indices.filter {
                !taken.contains($0) && all[$0].signals.usage.frecency > 1 && !all[$0].hasHotKey
            },
            signals: signals)
        var picked = Array(fresh) + used
        if picked.count < limit {
            taken.formUnion(used)
            let fill = all.indices
                .filter { !taken.contains($0) && all[$0].signals.alias == nil && !all[$0].hasHotKey }
                .compactMap { index in all[index].priority.map { (index: index, priority: $0) } }
                .sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.index < $1.index }
            picked += fill.map(\.index)
        }
        return picked.prefix(limit).map { items[$0] }
    }

    private static func isFreshInstall(_ traits: Traits, now: Date) -> Bool {
        guard traits.signals.usage.frecency <= 1, let installed = traits.installedAt else { return false }
        return now.timeIntervalSince(installed) < recentInstallWindow
    }
}
