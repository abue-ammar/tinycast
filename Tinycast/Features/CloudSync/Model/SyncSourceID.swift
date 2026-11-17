import CryptoKit
import Foundation

/// One kind of synced item; the raw value prefixes every record name, so it never changes.
enum SyncSourceID: String, CaseIterable, Codable, Sendable {
    case device, settings, launcherShortcuts, launcherLists, snippets, notes, quicklinks, chats
    case chatPresets, quickActions, mcpServers, extensions

    /// The category a key belongs to; nil for a device, which every Mac always shares.
    func category(of key: String) -> SyncCategory? {
        switch self {
        case .device: nil
        case .settings: SyncSettingScope.category(of: key)
        case .launcherShortcuts: .hotkeysAndAliases
        case .launcherLists: .favoritesAndFallbacks
        case .snippets: .snippets
        case .notes: .notes
        case .quicklinks: .quicklinks
        case .chats: .aiChats
        case .chatPresets, .quickActions: .aiCommands
        case .mcpServers: .mcpServers
        case .extensions: .extensions
        }
    }

    /// Hashed, so a file name or a path never becomes a CloudKit identifier.
    func recordName(for key: String) -> String {
        let digest = SHA256.hash(data: Data((rawValue + "\u{0}" + key).utf8))
        return rawValue + "." + digest.prefix(20).map { String(format: "%02x", $0) }.joined()
    }

    init?(recordName: String) {
        guard let prefix = recordName.split(separator: ".", maxSplits: 1).first else { return nil }
        self.init(rawValue: String(prefix))
    }
}

/// A content version: equal bytes, equal version, on every Mac.
enum SyncVersion {
    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
