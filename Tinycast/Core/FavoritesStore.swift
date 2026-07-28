import Foundation

/// Persists favorite apps as an ordered list of keys (bundle id, or file path when none), pinned to the top of the launcher when the search is empty.
@MainActor
final class FavoritesStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let key = "favoriteApps"

    @Published private(set) var keys: [String]

    init() {
        keys = defaults.stringArray(forKey: key) ?? []
    }

    func key(for app: AppEntry) -> String { app.preferenceKey }

    func isFavorite(_ app: AppEntry) -> Bool { keys.contains(key(for: app)) }

    /// Replace the whole favorites list at once (used when importing a settings backup).
    func replace(keys newKeys: [String]) {
        keys = newKeys
        defaults.set(keys, forKey: key)
    }

    func remove(keys removedKeys: Set<String>) {
        guard !removedKeys.isEmpty else { return }
        let updated = keys.filter { !removedKeys.contains($0) }
        guard updated != keys else { return }
        keys = updated
        defaults.set(keys, forKey: key)
    }

    func toggle(_ app: AppEntry) {
        let k = key(for: app)
        if let index = keys.firstIndex(of: k) {
            keys.remove(at: index)
        } else {
            keys.append(k)
        }
        defaults.set(keys, forKey: key)
    }

    /// Split `apps` into favorites (in stored order) and the rest (order preserved).
    func ordered(_ apps: [AppEntry]) -> (favorites: [AppEntry], rest: [AppEntry]) {
        guard !keys.isEmpty else { return ([], apps) }
        let byKey = Dictionary(
            apps.map { (key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let favorites = keys.compactMap { byKey[$0] }
        let favoriteKeys = Set(keys)
        let rest = apps.filter { !favoriteKeys.contains(key(for: $0)) }
        return (favorites, rest)
    }
}
