import Foundation
import OSLog

/// Aliases and hotkeys of content rows, which settings.json leaves out.
@MainActor
final class EntryShortcutSyncSource: SyncSource {
    private struct Shortcut: Codable, Equatable {
        var alias: String?
        var binding: HotKeyBinding?
    }

    private static let logger = Logger(subsystem: "com.tinycast", category: "CloudSync")
    private static let extensionPrefix = "extension:"
    private static let prefixes = [
        Quicklink.entryIDPrefix, CustomQuickAction.entryIDPrefix, StoredSnippet.entryIDPrefix,
        AppleShortcut.entryIDPrefix, extensionPrefix
    ]

    let id = SyncSourceID.launcherShortcuts
    private let aliases: AliasStore
    private let hotKeys: HotKeyManager
    /// Every row this Mac holds, listed in the launcher or not.
    private let rows: () -> Set<String>
    private let entryKeys: () -> SyncEntryKey

    init(
        aliases: AliasStore, hotKeys: HotKeyManager, rows: @escaping () -> Set<String>,
        entryKeys: @escaping () -> SyncEntryKey
    ) {
        self.aliases = aliases
        self.hotKeys = hotKeys
        self.rows = rows
        self.entryKeys = entryKeys
    }

    func observe() {
        _ = aliases.revision
        _ = hotKeys.revision
        _ = rows()
    }

    func snapshot() async -> [String: String]? {
        let entryKeys = entryKeys()
        var shortcuts: [String: Shortcut] = [:]
        for entryID in localEntryIDs() {
            guard let shortcut = shortcut(for: entryID) else { continue }
            shortcuts[entryKeys.portable(entryID)] = shortcut
        }
        return SyncPayload.snapshot(shortcuts)
    }

    func payload(for key: String) async -> Data? {
        shortcut(for: entryKeys().local(key)).flatMap(SyncPayload.encode)
    }

    /// A shortcut whose row isn't on this Mac yet waits for it, and a clashing chord stays local.
    func apply(_ changes: SyncChanges) async -> Set<String> {
        let entryKeys = entryKeys()
        let present = rows()
        var deferred: Set<String> = []
        for (key, payload) in changes.upserts {
            let entryID = entryKeys.local(key)
            guard present.contains(entryID) else {
                deferred.insert(key)
                continue
            }
            guard let shortcut = SyncPayload.decode(Shortcut.self, from: payload) else { continue }
            aliases.setAlias(shortcut.alias ?? "", for: entryID)
            guard let action = Self.action(for: entryID) else { continue }
            if let binding = shortcut.binding,
                let owner = hotKeys.conflictOwner(of: binding, excluding: action)
            {
                Self.logger.notice("A synced shortcut clashes with \(owner, privacy: .public)")
                continue
            }
            if hotKeys.binding(for: action) != shortcut.binding {
                hotKeys.setBinding(shortcut.binding, for: action)
            }
        }
        for key in changes.deletions {
            let entryID = entryKeys.local(key)
            aliases.setAlias("", for: entryID)
            if let action = Self.action(for: entryID), hotKeys.binding(for: action) != nil {
                hotKeys.setBinding(nil, for: action)
            }
        }
        return deferred
    }

    private func localEntryIDs() -> Set<String> {
        var ids = Set(aliases.aliases.keys.filter { key in Self.prefixes.contains { key.hasPrefix($0) } })
        ids.formUnion(hotKeys.boundQuicklinkIDs.compactMap { HotKeyAction.quicklink(id: $0).entryID })
        ids.formUnion(hotKeys.boundQuickActionIDs.compactMap { HotKeyAction.quickAction(id: $0).entryID })
        ids.formUnion(hotKeys.boundAppleShortcutIDs.compactMap { HotKeyAction.appleShortcut(id: $0).entryID })
        ids.formUnion(hotKeys.boundSnippetIDs.compactMap { HotKeyAction.snippet(id: $0).entryID })
        ids.formUnion(hotKeys.boundExtensionCommandEntryIDs)
        return ids
    }

    private func shortcut(for entryID: String) -> Shortcut? {
        let shortcut = Shortcut(
            alias: aliases.alias(for: entryID),
            binding: Self.action(for: entryID).flatMap(hotKeys.binding(for:)))
        return shortcut == Shortcut() ? nil : shortcut
    }

    private static func action(for entryID: String) -> HotKeyAction? {
        entryID.hasPrefix(extensionPrefix)
            ? .extensionCommand(entryID: entryID) : HotKeyAction(entryID: entryID)
    }
}
