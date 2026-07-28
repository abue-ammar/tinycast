import Foundation

/// Persists which launcher items and categories the user has hidden (only exclusions are stored); hiding affects the launcher list only, leaving favorites and hotkey bindings intact.
@MainActor
final class VisibilityStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let itemsKey = "hiddenLauncherItems"
    private let kindsKey = "hiddenLauncherKinds"

    @Published private(set) var hiddenItemKeys: Set<String>
    @Published private(set) var hiddenKinds: Set<String>

    init() {
        hiddenItemKeys = Set(defaults.stringArray(forKey: itemsKey) ?? [])
        hiddenKinds = Set(defaults.stringArray(forKey: kindsKey) ?? [])
    }

    /// Replace both exclusion sets at once (used when importing a settings backup).
    func replace(hiddenItems: [String], hiddenKinds newKinds: [String]) {
        hiddenItemKeys = Set(hiddenItems)
        hiddenKinds = Set(newKinds)
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
        defaults.set(Array(hiddenKinds), forKey: kindsKey)
    }

    func key(for entry: AppEntry) -> String { entry.preferenceKey }

    /// Whether the entry appears in the launcher: its category and the item itself must be on.
    func isVisible(_ entry: AppEntry) -> Bool {
        isKindVisible(entry.kind) && isItemVisible(entry)
    }

    func isItemVisible(_ entry: AppEntry) -> Bool {
        !hiddenItemKeys.contains(key(for: entry))
    }

    func setItemVisible(_ visible: Bool, for entry: AppEntry) {
        let k = key(for: entry)
        if visible { hiddenItemKeys.remove(k) } else { hiddenItemKeys.insert(k) }
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
    }

    func removeItemKeys(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let previous = hiddenItemKeys
        hiddenItemKeys.subtract(keys)
        guard hiddenItemKeys != previous else { return }
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
    }

    func isKindVisible(_ kind: AppEntry.Kind) -> Bool {
        !hiddenKinds.contains(kind.rawValue)
    }

    func setKindVisible(_ visible: Bool, for kind: AppEntry.Kind) {
        if visible { hiddenKinds.remove(kind.rawValue) } else { hiddenKinds.insert(kind.rawValue) }
        defaults.set(Array(hiddenKinds), forKey: kindsKey)
    }
}
