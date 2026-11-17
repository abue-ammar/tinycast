import Foundation

/// Launcher keys that name a place on this Mac, spelled so the same item matches on another one.
struct SyncEntryKey: Sendable {
    private static let snippetPrefix = "snippet:"
    private static let portableHome = "file:~/"

    let snippetFolder: URL
    let homeDirectory: URL

    func portable(_ key: String) -> String {
        if key.hasPrefix(Self.snippetPrefix) {
            let path = String(key.dropFirst(Self.snippetPrefix.count))
            let folder = snippetFolder.standardizedFileURL.path + "/"
            guard path.hasPrefix(folder) else { return key }
            return Self.snippetPrefix + path.dropFirst(folder.count)
        }
        let home = homeDirectory.standardizedFileURL.absoluteString
        if key.hasPrefix(home) { return Self.portableHome + key.dropFirst(home.count) }
        return key
    }

    func local(_ key: String) -> String {
        if key.hasPrefix(Self.snippetPrefix) {
            let name = String(key.dropFirst(Self.snippetPrefix.count))
            guard !name.hasPrefix("/") else { return key }
            return Self.snippetPrefix
                + snippetFolder.appending(path: name).standardizedFileURL.path
        }
        if key.hasPrefix(Self.portableHome) {
            return homeDirectory.standardizedFileURL.absoluteString
                + key.dropFirst(Self.portableHome.count)
        }
        return key
    }
}
