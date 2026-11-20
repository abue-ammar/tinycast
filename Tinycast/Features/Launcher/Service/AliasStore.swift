import Foundation

/// The user's per-entry aliases, keyed like favorites and ranking by `preferenceKey`.
@MainActor
@Observable
final class AliasStore {
    private static let defaultsKey = "launcherAliases"
    private let defaults: UserDefaults

    private(set) var aliases: [String: String]
    /// AppIndex includes this in its result key, invalidating a ranking when an alias changes.
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aliases = Self.stored(in: defaults)
    }

    /// Adopts what another process stored, without writing it back.
    func reload() {
        let stored = Self.stored(in: defaults)
        guard stored != aliases else { return }
        aliases = stored
        revision &+= 1
    }

    private static func stored(in defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    func alias(for entryKey: String) -> String? { aliases[entryKey] }

    /// Stored as typed — trimming here would eat the space mid-word — but blank still means none.
    func setAlias(_ alias: String, for entryKey: String) {
        let value = alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : alias
        guard aliases[entryKey] != value else { return }
        aliases[entryKey] = value
        revision &+= 1
        defaults.set(aliases, forKey: Self.defaultsKey)
    }

    func removeKeys(_ keys: Set<String>) {
        let remaining = aliases.filter { !keys.contains($0.key) }
        guard remaining.count != aliases.count else { return }
        aliases = remaining
        revision &+= 1
        defaults.set(aliases, forKey: Self.defaultsKey)
    }

    func replace(_ new: [String: String]) {
        // An import obeys the same rule as typing: blank means none, or it lands unclearable.
        aliases = new.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        revision &+= 1
        defaults.set(aliases, forKey: Self.defaultsKey)
    }
}
