import Foundation

/// A category that is off runs nothing, so it gates shortcuts as well as the list.
@MainActor
@Observable
final class VisibilityStore {
    private static let itemsKey = "hiddenLauncherItems"
    private static let kindsKey = "hiddenLauncherKinds"
    private let defaults: UserDefaults

    private(set) var hiddenItemKeys: Set<String>
    private(set) var disabledKinds: Set<String>
    /// AppIndex includes this in its result key, invalidating a list when the visible set moves.
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenItemKeys = Set(defaults.stringArray(forKey: Self.itemsKey) ?? [])
        disabledKinds = Set(defaults.stringArray(forKey: Self.kindsKey) ?? [])
    }

    /// Adopts what another process stored, without writing it back.
    func reload() {
        let items = Set(defaults.stringArray(forKey: Self.itemsKey) ?? [])
        let kinds = Set(defaults.stringArray(forKey: Self.kindsKey) ?? [])
        guard items != hiddenItemKeys || kinds != disabledKinds else { return }
        hiddenItemKeys = items
        disabledKinds = kinds
        revision &+= 1
    }

    func replace(hiddenItems: [String], disabledKinds newKinds: [String]) {
        hiddenItemKeys = Set(hiddenItems)
        disabledKinds = Set(newKinds)
        revision &+= 1
        defaults.set(Array(hiddenItemKeys), forKey: Self.itemsKey)
        defaults.set(Array(disabledKinds), forKey: Self.kindsKey)
    }

    func key(for entry: AppEntry) -> String { entry.preferenceKey }

    /// Whether the entry appears in the launcher: its category and the item itself must be on.
    func isVisible(_ entry: AppEntry) -> Bool {
        isCategoryEnabled(entry) && isItemVisible(entry)
    }

    /// An entry a feature pane owns answers to that feature's switch, so no category gates it.
    private func isCategoryEnabled(_ entry: AppEntry) -> Bool {
        entry.settingsOwner != nil || isKindEnabled(entry.kind)
    }

    func isItemVisible(_ entry: AppEntry) -> Bool { isItemVisible(key: key(for: entry)) }

    func isItemVisible(key: String) -> Bool { !hiddenItemKeys.contains(key) }

    func setItemVisible(_ visible: Bool, for entry: AppEntry) {
        setItemVisible(visible, forKey: key(for: entry))
    }

    func setItemVisible(_ visible: Bool, forKey key: String) {
        guard isItemVisible(key: key) != visible else { return }
        if visible { hiddenItemKeys.remove(key) } else { hiddenItemKeys.insert(key) }
        revision &+= 1
        defaults.set(Array(hiddenItemKeys), forKey: Self.itemsKey)
    }

    func removeItemKeys(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let previous = hiddenItemKeys
        hiddenItemKeys.subtract(keys)
        guard hiddenItemKeys != previous else { return }
        revision &+= 1
        defaults.set(Array(hiddenItemKeys), forKey: Self.itemsKey)
    }

    func isKindEnabled(_ kind: AppEntry.Kind) -> Bool {
        !disabledKinds.contains(kind.rawValue)
    }

    func setKindEnabled(_ enabled: Bool, for kind: AppEntry.Kind) {
        guard isKindEnabled(kind) != enabled else { return }
        if enabled { disabledKinds.remove(kind.rawValue) } else { disabledKinds.insert(kind.rawValue) }
        revision &+= 1
        defaults.set(Array(disabledKinds), forKey: Self.kindsKey)
    }

    /// A feature carrying its own switch is not this store's to gate.
    func allowsHotKey(_ action: HotKeyAction) -> Bool {
        switch action {
        case .app: isKindEnabled(.application)
        case .settingsPane: isKindEnabled(.systemSettings)
        case .systemAction: isKindEnabled(.systemAction)
        case .command(let id): id.owner == nil ? isKindEnabled(.command) : true
        case .togglePalette, .dictation, .quickAction, .customCommand, .windowCommand, .customWindowSize,
            .windowLayout, .windowRoom, .quicklink, .appleShortcut, .snippet, .extensionCommand:
            true
        }
    }
}
