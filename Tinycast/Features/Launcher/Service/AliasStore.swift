import Foundation

/// The user's per-entry aliases, keyed like favorites and ranking by `preferenceKey`.
@MainActor
@Observable
final class AliasStore {
    private let defaults = UserDefaults.standard
    private let defaultsKey = "launcherAliases"

    private(set) var aliases: [String: String]
    /// AppIndex includes this in its result key, invalidating a ranking when an alias changes.
    private(set) var revision = 0

    init() {
        aliases = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    func alias(for entryKey: String) -> String? { aliases[entryKey] }

    /// Stored as typed — trimming here would eat the space mid-word — but blank still means none.
    func setAlias(_ alias: String, for entryKey: String) {
        let value = alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : alias
        guard aliases[entryKey] != value else { return }
        aliases[entryKey] = value
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    func removeKeys(_ keys: Set<String>) {
        let remaining = aliases.filter { !keys.contains($0.key) }
        guard remaining.count != aliases.count else { return }
        aliases = remaining
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    /// Replace the whole table at once (used when importing a settings backup).
    func replace(_ new: [String: String]) {
        // An import obeys the same rule as typing: blank means none, or it lands unclearable.
        aliases = new.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }
}
