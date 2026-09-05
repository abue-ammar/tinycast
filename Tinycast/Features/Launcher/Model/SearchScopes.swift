import Foundation

/// The folders and bundles `AppIndex` scans for applications.
enum SearchScopes {
    /// Seeded on a fresh install; order matters, the scan deduping by bundle ID.
    static let defaults: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        // Cryptex-delivered system apps; the `/Applications` Safari is a hidden symlink.
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        // The one user-facing app in CoreServices, so the directory itself is no default.
        "/System/Library/CoreServices/Finder.app",
        "~/Applications"
    ]

    /// Tilde-abbreviated and unslashed, so a settings backup stays portable across machines.
    static func abbreviate(_ path: String) -> String {
        let trimmed = trimTrailingSlash(path)
        return (trimmed as NSString).abbreviatingWithTildeInPath
    }

    static func expand(_ path: String) -> String {
        (trimTrailingSlash(path) as NSString).expandingTildeInPath
    }

    /// Abbreviates every path and drops duplicates, preserving order.
    static func normalize(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map(abbreviate).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Every `.app` the scopes point at. One subfolder deep; deeper nesting needs its own scope.
    static func appBundles(in scopes: [String]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for scope in scopes {
            let url = URL(fileURLWithPath: expand(scope))
            if url.pathExtension == "app" {
                if fm.fileExists(atPath: url.path) { result.append(url) }
                continue
            }
            result.append(contentsOf: appBundles(under: url, subfolderDepth: 1))
        }
        return result
    }

    private static let scanKeys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
    private static let scanKeySet: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]

    /// `.app` is a leaf here — never descended into.
    private static func appBundles(under url: URL, subfolderDepth: Int) -> [URL] {
        let fm = FileManager.default
        guard
            let items = (try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: scanKeys, options: [.skipsHiddenFiles]))
                ?? (try? fm.contentsOfDirectory(
                    at: url.resolvingSymlinksInPath(),
                    includingPropertiesForKeys: scanKeys,
                    options: [.skipsHiddenFiles]))
        else { return [] }

        var result: [URL] = []
        for item in items {
            let logicalItem = url.appendingPathComponent(item.lastPathComponent)
            let isApp = logicalItem.pathExtension == "app"
            let values = try? item.resourceValues(forKeys: scanKeySet)
            let isSymlink = values?.isSymbolicLink == true

            if isApp {
                if !isSymlink || fm.fileExists(atPath: logicalItem.path) {
                    result.append(logicalItem)
                }
            } else if subfolderDepth > 0 {
                if values?.isDirectory == true {
                    result.append(
                        contentsOf: appBundles(under: logicalItem, subfolderDepth: subfolderDepth - 1))
                } else if isSymlink,
                    (try? logicalItem.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?
                        .isDirectory == true
                {
                    result.append(
                        contentsOf: appBundles(under: logicalItem, subfolderDepth: subfolderDepth - 1))
                }
            }
        }
        return result
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
