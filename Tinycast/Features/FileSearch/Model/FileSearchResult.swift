import Foundation

struct FileSearchResult: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    let parentPath: String
    let isDirectory: Bool

    init(url: URL, isDirectory: Bool, homeDirectory: URL) {
        let url = url.standardizedFileURL
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.parentPath = Self.abbreviate(
            url.deletingLastPathComponent().path,
            homePath: homeDirectory.standardizedFileURL.path)
        self.isDirectory = isDirectory
    }

    private static func abbreviate(_ path: String, homePath: String) -> String {
        if path == homePath { return "~" }
        guard path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }
}
