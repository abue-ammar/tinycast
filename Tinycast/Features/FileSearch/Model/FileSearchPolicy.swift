import Foundation

/// Decides what a configured scope list means: which roots Spotlight takes as-is, and what to drop.
struct FileSearchPolicy: Sendable, Equatable {
    let homeDirectory: URL
    /// Home is held apart because `~/Library` can never be a scope, so it has to be expanded instead.
    let directRoots: [URL]
    let includesHome: Bool
    let ignore: FileSearchIgnoreList

    init(scopes: [String], ignorePatterns: [String], homeDirectory: URL) {
        self.homeDirectory = homeDirectory
        let home = homeDirectory.standardizedFileURL.path
        let roots = FileSearchScope.roots(for: scopes, homeDirectory: homeDirectory)
        directRoots = roots.filter { $0.path != home }
        includesHome = roots.count != directRoots.count
        ignore = FileSearchIgnoreList(patterns: FileSearchIgnoreList.defaults + ignorePatterns)
    }
}
