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

    /// `.app` is a leaf here — never descended into.
    private static func appBundles(under url: URL, subfolderDepth: Int) -> [URL] {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: url.resolvingSymlinksInPath(),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var result: [URL] = []
        for item in items {
            let logicalURL = url.appendingPathComponent(item.lastPathComponent)
            if logicalURL.pathExtension == "app" {
                if FileManager.default.fileExists(atPath: logicalURL.path) {
                    result.append(logicalURL)
                }
            } else if subfolderDepth > 0, isDirectory(at: logicalURL) {
                result.append(
                    contentsOf: appBundles(
                        under: logicalURL,
                        subfolderDepth: subfolderDepth - 1))
            }
        }
        return result
    }

    private static func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            && isDir.boolValue
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
