import Foundation

@MainActor
@Observable
final class FavoritesStore {
    private static let defaultsKey = "favoriteApps"
    private let defaults: UserDefaults

    private(set) var keys: [String]
    /// AppIndex includes this in its result key, invalidating a list when the pinning changes.
    private(set) var revision = 0

    enum Item: Identifiable, Equatable, Sendable {
        case entry(AppEntry)
        case file(FileSearchResult)

        var id: String {
            switch self {
            case .entry(let entry): entry.id
            case .file(let file): "file-" + file.id
            }
        }

        var key: String {
            switch self {
            case .entry(let entry): entry.preferenceKey
            case .file(let file): file.favoriteKey
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keys = defaults.stringArray(forKey: Self.defaultsKey) ?? []
    }

    /// Adopts what another process stored, without writing it back.
    func reload() {
        let stored = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        guard stored != keys else { return }
        keys = stored
        revision &+= 1
    }

    func key(for app: AppEntry) -> String { app.preferenceKey }

    func isFavorite(_ app: AppEntry) -> Bool { keys.contains(key(for: app)) }

    func isFavorite(_ file: FileSearchResult) -> Bool { keys.contains(file.favoriteKey) }

    func files(homeDirectory: URL) -> [FileSearchResult] {
        keys.compactMap { FileSearchResult(favoriteKey: $0, homeDirectory: homeDirectory) }
    }

    func orderedItems(entries: [AppEntry], files: [FileSearchResult]) -> [Item] {
        guard !keys.isEmpty else { return [] }
        let items = entries.map(Item.entry) + files.map(Item.file)
        let byKey = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return keys.compactMap { byKey[$0] }
    }

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
        toggle(key: key(for: app))
    }

    func toggle(_ file: FileSearchResult) {
        toggle(key: file.favoriteKey)
    }

    private func toggle(key: String) {
        if let index = keys.firstIndex(of: key) {
            keys.remove(at: index)
        } else {
            keys.append(key)
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
        defaults.set(keys, forKey: Self.defaultsKey)
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
