import Foundation

@MainActor
final class LauncherListSyncSource: SyncSource {
    private struct Fallbacks: Codable {
        var order: [String]
        var disabled: [String]
    }

    private static let favoritesKey = "favorites"
    private static let fallbacksKey = "fallbacks"
    /// A synced list may turn it off, never on: it runs what the query says.
    private static let shellFallback = Fallback.builtin(.runShellCommand).id

    let id = SyncSourceID.launcherLists
    private let favorites: FavoritesStore
    private let fallbacks: FallbackStore
    private let entryKeys: () -> SyncEntryKey

    init(favorites: FavoritesStore, fallbacks: FallbackStore, entryKeys: @escaping () -> SyncEntryKey) {
        self.favorites = favorites
        self.fallbacks = fallbacks
        self.entryKeys = entryKeys
    }

    func observe() {
        _ = favorites.keys
        _ = fallbacks.orderedIDs
        _ = fallbacks.disabledIDs
    }

    func snapshot() async -> [String: String]? {
        var versions: [String: String] = [:]
        for key in [Self.favoritesKey, Self.fallbacksKey] {
            versions[key] = payload(key).map(SyncVersion.of)
        }
        return versions
    }

    func payload(for key: String) async -> Data? {
        payload(key)
    }

    func apply(_ changes: SyncChanges) async -> Set<String> {
        if let data = changes.upserts[Self.favoritesKey],
            let keys = SyncPayload.decode([String].self, from: data)
        {
            let entryKeys = entryKeys()
            favorites.replace(keys: keys.map(entryKeys.local))
        }
        if let data = changes.upserts[Self.fallbacksKey],
            let incoming = SyncPayload.decode(Fallbacks.self, from: data)
        {
            var disabled = Set(incoming.disabled)
            if fallbacks.disabledIDs.contains(Self.shellFallback) { disabled.insert(Self.shellFallback) }
            fallbacks.replace(order: incoming.order, disabled: disabled)
        }
        return []
    }

    private func payload(_ key: String) -> Data? {
        switch key {
        case Self.favoritesKey:
            let entryKeys = entryKeys()
            return SyncPayload.encode(favorites.keys.map(entryKeys.portable))
        case Self.fallbacksKey:
            return SyncPayload.encode(
                Fallbacks(order: fallbacks.orderedIDs, disabled: fallbacks.disabledIDs.sorted()))
        default:
            return nil
        }
    }
}
