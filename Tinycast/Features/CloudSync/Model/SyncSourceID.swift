import CryptoKit
import Foundation

/// One kind of synced item; the raw value prefixes every record name, so it never changes.
enum SyncSourceID: String, CaseIterable, Codable, Sendable {
    case device, settings, launcherShortcuts, launcherLists, snippets, notes, quicklinks, chats
    case chatPresets, quickActions, mcpServers, extensions, clipboardText, clipboardImages

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
        case .clipboardText: .clipboardText
        case .clipboardImages: .clipboardImages
        }
    }

    /// Hashed, so a file name or a path never becomes a CloudKit identifier.
    func recordName(for key: String) -> String {
        let digest = SHA256.hash(data: Data((rawValue + "\u{0}" + key).utf8))
        return rawValue + "." + hex(digest.prefix(20))
    }

    init?(recordName: String) {
        guard let prefix = recordName.split(separator: ".", maxSplits: 1).first else { return nil }
        self.init(rawValue: String(prefix))
    }
}

/// A content version: equal bytes, equal version, on every Mac.
enum SyncVersion {
    static func of(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }
}

/// Lowercase hex without `String(format:)`, which costs a microsecond a byte on every key.
private func hex(_ bytes: some Sequence<UInt8>) -> String {
    let digits = Array("0123456789abcdef".utf8)
    let bytes = Array(bytes)
    return String(unsafeUninitializedCapacity: bytes.count * 2) { buffer in
        for (index, byte) in bytes.enumerated() {
            buffer[2 * index] = digits[Int(byte >> 4)]
            buffer[2 * index + 1] = digits[Int(byte & 0x0f)]
        }
        return bytes.count * 2
    }
}
