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

    /// Where a bundle ships its own apps: Xcode keeps Instruments and Simulator there.
    private static let embeddedAppFolders = [
        "Contents/Applications", "Contents/Developer/Applications"
    ]

    /// Every `.app` the scopes point at. One subfolder deep; deeper nesting needs its own scope.
    static func appBundles(in scopes: [String]) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        for scope in scopes {
            let url = URL(fileURLWithPath: expand(scope))
            if url.pathExtension == "app" {
                if fm.fileExists(atPath: url.path) { result.append(contentsOf: withEmbedded(url)) }
                continue
            }
            result.append(contentsOf: appBundles(under: url, subfolderDepth: 1))
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// An `.app` is never descended into beyond its embedded-app folders.
    private static func appBundles(
        under url: URL, subfolderDepth: Int, ancestors: Set<String> = []
    ) -> [URL] {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        // Skip non-directories early without rejecting directory symlinks.
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return [] }
        let resolved = url.resolvingSymlinksInPath()
        guard
            !ancestors.contains(resolved.path),
            let items = try? fm.contentsOfDirectory(
                at: resolved, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
        else { return [] }
        let ancestors = ancestors.union([resolved.path])
        // Keep logical app paths stable when a directory link points to a new target.
        let scopedItems =
            items.first?.deletingLastPathComponent().path == url.path
            ? items
            : items.map {
                url.appendingPathComponent($0.lastPathComponent, isDirectory: $0.hasDirectoryPath)
            }

        var result: [URL] = []
        for item in newestFirst(scopedItems) {
            if item.pathExtension == "app" {
                result.append(contentsOf: withEmbedded(item, ancestors: ancestors))
            } else if subfolderDepth > 0 {
                result.append(
                    contentsOf: appBundles(
                        under: item, subfolderDepth: subfolderDepth - 1, ancestors: ancestors))
            }
        }
        return result
    }

    /// The scan keeps a bundle ID's first copy, so a folder lists its newest version first.
    private static func newestFirst(_ items: [URL]) -> [URL] {
        items
            .map { (url: $0, version: shortVersion(of: $0)) }
            .sorted { lhs, rhs in
                let byVersion = lhs.version.compare(rhs.version, options: .numeric)
                if byVersion != .orderedSame { return byVersion == .orderedDescending }
                // A tie falls back to Finder's order, so the filesystem never picks the winner.
                return displayName(of: lhs.url).localizedStandardCompare(displayName(of: rhs.url))
                    == .orderedAscending
            }
            .map(\.url)
    }

    /// Empty when unreadable, which `.numeric` ranks below every real version.
    private static func shortVersion(of url: URL) -> String {
        guard url.pathExtension == "app" else { return "" }
        return Bundle(url: url)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Without `.app`, so `Xcode` sorts before `Xcode-beta` rather than after it.
    private static func displayName(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private static func withEmbedded(_ app: URL, ancestors: Set<String> = []) -> [URL] {
        [app]
            + embeddedAppFolders.flatMap {
                appBundles(under: app.appendingPathComponent($0), subfolderDepth: 0, ancestors: ancestors)
            }
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
