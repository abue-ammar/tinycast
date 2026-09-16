import Foundation

/// Owns the custom-size library: its launcher presence, its edits, and a deletion's cleanup.
@MainActor
final class CustomWindowSizeCoordinator {
    private let store: CustomWindowSizeStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    /// Dialog presentation only. Never state this type owns.
    private unowned let core: AppCore

    init(
        store: CustomWindowSizeStore, settings: AppSettings, appIndex: AppIndex,
        hotKeys: HotKeyManager, favorites: FavoritesStore, visibility: VisibilityStore,
        ranking: LauncherRankingStore, aliases: AliasStore, core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.core = core
    }

    /// Custom sizes are window commands, so they follow the commands' own launcher switch.
    func applyCustomWindowSizesPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setCustomWindowSizes(visible ? store.sizes : [])
    }

    @discardableResult
    func addCustomWindowSize(
        _ draft: CustomWindowSize
    ) throws(CustomWindowSizeValidationError) -> CustomWindowSize {
        try store.add(draft)
    }

    func updateCustomWindowSize(_ draft: CustomWindowSize) throws(CustomWindowSizeValidationError) {
        try store.update(draft)
    }

    func deleteCustomWindowSize(id: UUID) async {
        guard let size = store.size(id: id),
            await core.confirm(
                title: "Delete “\(size.name)”?",
                message: "Its shortcut and launcher references go with it.",
                symbol: CustomWindowSize.sfSymbol, confirmTitle: "Delete"),
            store.remove(id: id) != nil
        else { return }
        // Unwound only once the row is gone, so a kept record never loses its shortcut.
        removeReferences(ids: [size.id], entryIDs: [size.entryID])
    }

    @discardableResult
    func replaceCustomWindowSizes(_ incoming: [CustomWindowSize]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.sizes.map { ($0.id, $0.entryID) })
        let count = store.replace(with: incoming)
        let removed = Set(previous.keys).subtracting(store.sizes.map(\.id))
        removeReferences(ids: removed, entryIDs: Set(removed.compactMap { previous[$0] }))
        return count
    }

    private func removeReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.customWindowSize(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }
}
