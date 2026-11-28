import Foundation

/// One command of one extension, and the only spelling of its launcher entry ID.
nonisolated struct ExtensionCommandID: Codable, Hashable, Sendable {
    /// Never `extension:`: the removed Raycast runtime wrote that, and its cleanup still deletes it.
    static let entryIDPrefix = "extension-command:"

    let extensionID: String
    let command: String

    /// Neither part holds a `/`: the manifest's rules keep both to lowercase words and dashes.
    var path: String { "\(extensionID)/\(command)" }
    var entryID: String { Self.entryIDPrefix + path }

    init(extensionID: String, command: String) {
        self.extensionID = extensionID
        self.command = command
    }

    init?(entryID: String) {
        guard entryID.hasPrefix(Self.entryIDPrefix) else { return nil }
        let parts = entryID.dropFirst(Self.entryIDPrefix.count)
            .split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        self.init(extensionID: String(parts[0]), command: String(parts[1]))
    }
}
