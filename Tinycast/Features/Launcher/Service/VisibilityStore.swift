import Foundation

/// Which items are hidden from the launcher, and which categories are switched on at all. A
/// category that is off runs nothing, so it gates shortcuts as well as the list.
@MainActor
@Observable
final class VisibilityStore {
    private let defaults = UserDefaults.standard
    private let itemsKey = "hiddenLauncherItems"
    private let kindsKey = "hiddenLauncherKinds"

    private(set) var hiddenItemKeys: Set<String>
    private(set) var disabledKinds: Set<String>
    /// AppIndex includes this in its result key, invalidating a list when the visible set moves.
    private(set) var revision = 0

    init() {
        hiddenItemKeys = Set(defaults.stringArray(forKey: itemsKey) ?? [])
        disabledKinds = Set(defaults.stringArray(forKey: kindsKey) ?? [])
    }

    /// Replace both exclusion sets at once (used when importing a settings backup).
    func replace(hiddenItems: [String], disabledKinds newKinds: [String]) {
        hiddenItemKeys = Set(hiddenItems)
        disabledKinds = Set(newKinds)
        revision &+= 1
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
        defaults.set(Array(disabledKinds), forKey: kindsKey)
    }

    func key(for entry: AppEntry) -> String { entry.preferenceKey }

    /// Whether the entry appears in the launcher: its category and the item itself must be on.
    func isVisible(_ entry: AppEntry) -> Bool {
        isKindEnabled(entry.kind) && isItemVisible(entry)
    }

    func isItemVisible(_ entry: AppEntry) -> Bool {
        !hiddenItemKeys.contains(key(for: entry))
    }

    func setItemVisible(_ visible: Bool, for entry: AppEntry) {
        let k = key(for: entry)
        if visible { hiddenItemKeys.remove(k) } else { hiddenItemKeys.insert(k) }
        revision &+= 1
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
    }

    func removeItemKeys(_ keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let previous = hiddenItemKeys
        hiddenItemKeys.subtract(keys)
        guard hiddenItemKeys != previous else { return }
        revision &+= 1
        defaults.set(Array(hiddenItemKeys), forKey: itemsKey)
    }

    func isKindEnabled(_ kind: AppEntry.Kind) -> Bool {
        !disabledKinds.contains(kind.rawValue)
    }

    func setKindEnabled(_ enabled: Bool, for kind: AppEntry.Kind) {
        if enabled { disabledKinds.remove(kind.rawValue) } else { disabledKinds.insert(kind.rawValue) }
        revision &+= 1
        defaults.set(Array(disabledKinds), forKey: kindsKey)
    }

    /// Whether a shortcut may run, the way each feature switch already guards its own funnel. An
    /// action belonging to a feature that carries its own switch is not this store's to gate.
    func allowsHotKey(_ action: HotKeyAction) -> Bool {
        switch action {
        case .app: isKindEnabled(.application)
        case .settingsPane: isKindEnabled(.systemSettings)
        case .systemAction: isKindEnabled(.systemAction)
        case .toggleClipboard, .toggleEmoji, .showNotes, .createNote, .searchNotes, .searchFiles,
            .searchSnippets, .joinNextMeeting, .mySchedule, .createEvent, .aiChat, .quickAction:
            isKindEnabled(.command)
        case .togglePalette, .customCommand, .windowCommand, .quicklink, .extensionCommand:
            true
        }
    }
}
