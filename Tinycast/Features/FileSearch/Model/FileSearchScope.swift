import Foundation

enum FileSearchScope {
    /// Stored tilde-abbreviated, so a settings backup stays portable between machines.
    static let defaultScopes = ["~"]

    struct Candidate: Sendable {
        let url: URL
        let isDirectory: Bool
        let isHidden: Bool
        let isPackage: Bool
    }

    /// Home's children that Spotlight's recents query may search: scoping it to home pulls in Library.
    static func select(_ candidates: [Candidate]) -> [URL] {
        candidates.filter { candidate in
            candidate.isDirectory && !candidate.isPackage && !candidate.isHidden
                && candidate.url.lastPathComponent.caseInsensitiveCompare("Library") != .orderedSame
        }.map(\.url)
    }

    static func expand(_ scope: String, homeDirectory: URL) -> URL {
        guard scope.hasPrefix("~") else {
            return URL(fileURLWithPath: scope, isDirectory: true).standardizedFileURL
        }
        let relative = String(scope.dropFirst()).trimmingPrefix("/")
        guard !relative.isEmpty else { return homeDirectory.standardizedFileURL }
        return homeDirectory.appending(path: relative, directoryHint: .isDirectory)
            .standardizedFileURL
    }

    static func abbreviate(_ path: String, homeDirectory: URL) -> String {
        let home = homeDirectory.standardizedFileURL.path
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// Abbreviated and deduplicated, keeping the order the user added them in.
    static func normalize(_ scopes: [String], homeDirectory: URL) -> [String] {
        var seen = Set<String>()
        let abbreviated = roots(for: scopes, homeDirectory: homeDirectory)
            .map { abbreviate($0.path, homeDirectory: homeDirectory) }
        return abbreviated.filter { seen.insert($0).inserted }
    }

    static func roots(for scopes: [String], homeDirectory: URL) -> [URL] {
        var seen = Set<String>()
        let expanded = scopes.map { expand($0, homeDirectory: homeDirectory) }
        return expanded.filter { seen.insert($0.path).inserted }
    }
}
