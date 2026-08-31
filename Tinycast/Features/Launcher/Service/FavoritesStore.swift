import Foundation

/// Favorite apps as an ordered key list, pinned to the top while the search is empty.
@MainActor
@Observable
final class FavoritesStore {
    private let defaults = UserDefaults.standard
    private let key = "favoriteApps"

    private(set) var keys: [String]
    /// AppIndex includes this in its result key, invalidating a list when the pinning changes.
    private(set) var revision = 0

    init() {
        keys = defaults.stringArray(forKey: key) ?? []
    }

    func key(for app: AppEntry) -> String { app.preferenceKey }

    func isFavorite(_ app: AppEntry) -> Bool { keys.contains(key(for: app)) }

    /// Replace the whole favorites list at once (used when importing a settings backup).
    func replace(keys newKeys: [String]) {
        keys = newKeys
        commit()
    }

    func remove(keys removedKeys: Set<String>) {
        guard !removedKeys.isEmpty else { return }
        let updated = keys.filter { !removedKeys.contains($0) }
        guard updated != keys else { return }
        keys = updated
        commit()
    }

    func toggle(_ app: AppEntry) {
        let k = key(for: app)
        if let index = keys.firstIndex(of: k) {
            keys.remove(at: index)
        } else {
            keys.append(k)
        }
        commit()
    }

    /// The pair comes from the visible order, so hidden entries keep their slots.
    func exchange(_ first: String, with second: String) {
        guard let a = keys.firstIndex(of: first), let b = keys.firstIndex(of: second), a != b else {
            return
        }
        keys.swapAt(a, b)
        commit()
    }

    private func commit() {
        revision &+= 1
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
