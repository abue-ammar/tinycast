import Foundation

struct FileSearchPolicy: Sendable, Equatable {
    struct Request: Codable, Sendable, Equatable {
        let scopes: [String]
        let ignorePatterns: [String]
        let includesHiddenFiles: Bool
        let homeDirectory: String
    }

    let request: Request
    let homeDirectory: URL
    let roots: [String]
    let ignore: FileSearchIgnoreList
    /// Stable across processes, unlike `Hasher`, so a stored index can be matched to its settings.
    let fingerprint: UInt64
    private let homePath: String

    private static let systemFolders: Set<Substring> = [
        "System", "Library", "usr", "private", "bin", "sbin", "opt", "cores", "dev", "var", "etc",
        "tmp", "Volumes"
    ]
    private static let bundleExtensions: Set<String> = [
        "app", "appex", "framework", "bundle", "plugin", "kext", "xpc", "photoslibrary"
    ]
    private static let cloudDrives = [
        "/Library/CloudStorage", "/Library/Mobile Documents/com~apple~CloudDocs"
    ]

    var includesHiddenFiles: Bool { request.includesHiddenFiles }

    init(scopes: [String], ignorePatterns: [String], includesHiddenFiles: Bool, homeDirectory: URL) {
        self.init(
            Request(
                scopes: scopes, ignorePatterns: ignorePatterns,
                includesHiddenFiles: includesHiddenFiles, homeDirectory: homeDirectory.path))
    }

    init(_ request: Request) {
        self.request = request
        homeDirectory = URL(filePath: request.homeDirectory, directoryHint: .isDirectory)
        // Not standardized: that drops a leading `/private`, and the crawl compares real paths.
        homePath = homeDirectory.path
        roots = FileSearchScope.roots(for: request.scopes, homeDirectory: homeDirectory)
        ignore = FileSearchIgnoreList(patterns: request.ignorePatterns, homeDirectory: homeDirectory)
        let visibility = request.includesHiddenFiles ? "hidden" : "visible"
        fingerprint = Self.fnv1a(
            ([visibility] + roots + ["\0"] + request.ignorePatterns).joined(separator: "\n"))
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.request == rhs.request }

    /// A folder's files inherit its prior, so it is worked out once per folder.
    func prior(of path: String) -> Int8 {
        if FileSearchScope.contains(homePath, path) {
            let rest = path.dropFirst(homePath.count)
            for cloud in Self.cloudDrives where rest == cloud || rest.hasPrefix(cloud + "/") {
                return Self.prior(of: rest.dropFirst(cloud.count), plain: 2)
            }
            if rest == "/Library" || rest.hasPrefix("/Library/") { return 0 }
            return Self.prior(of: rest, plain: 2)
        }
        if let top = path.split(separator: "/").first, Self.systemFolders.contains(top) { return 0 }
        return Self.prior(of: path[...], plain: 1)
    }

    /// A bundle's insides are never the user's own files; a hidden folder's are, just less often.
    private static func prior(of path: Substring, plain: Int8) -> Int8 {
        var prior = plain
        for component in path.split(separator: "/") {
            if let dot = component.lastIndex(of: "."),
                bundleExtensions.contains(component[component.index(after: dot)...].lowercased())
            {
                return 0
            }
            if component.hasPrefix(".") { prior = min(prior, 1) }
        }
        return prior
    }

    private static func fnv1a(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}
