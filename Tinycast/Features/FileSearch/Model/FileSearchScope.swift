import Foundation

/// The configured scopes are the crawl roots: only what lies under one is indexed or searched.
enum FileSearchScope {
    /// Stored tilde-abbreviated, so a backup stays portable.
    static let defaultScopes = ["~"]

    static func expand(_ scope: String, homeDirectory: URL) -> URL {
        guard scope.hasPrefix("~") else {
            return URL(filePath: scope, directoryHint: .isDirectory).standardizedFileURL
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

    /// Keeps a scope inside another as the user listed it; only `roots(for:)` folds it.
    static func normalize(_ scopes: [String], homeDirectory: URL) -> [String] {
        var seen = Set<String>()
        return scopes.compactMap { scope in
            let path = expand(scope, homeDirectory: homeDirectory).path
            return seen.insert(path).inserted ? abbreviate(path, homeDirectory: homeDirectory) : nil
        }
    }

    static func roots(for scopes: [String], homeDirectory: URL) -> [String] {
        var seen = Set<String>()
        let paths = scopes.map { expand($0, homeDirectory: homeDirectory).path }
            .filter { seen.insert($0).inserted }
        return paths.filter { path in
            !paths.contains { $0 != path && contains($0, path) }
        }
    }

    static func contains(_ root: String, _ path: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }
}
