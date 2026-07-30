import Foundation

/// One thing an uninstall would remove: the app bundle itself, or a support file it left behind.
struct LeftoverItem: Identifiable, Hashable, Sendable {
    /// Which group the row belongs to, and the order the two groups render in.
    enum Kind: Int, Sendable {
        case bundle
        case support
    }

    let url: URL
    let kind: Kind
    /// Bytes on disk, or nil when the size couldn't be measured.
    let size: Int64?
    /// False for a path this app can't remove — a locked row: shown for what it is, never checked, and
    /// not togglable. Cheaper on the user than checking it and reporting the failure afterwards.
    var isRemovable: Bool = true
    /// Whether the path is a directory, resolved once at discovery. Carried on the row because the only
    /// consumer is the trailing glyph, and asking the filesystem from a view body would stat on every
    /// re-render — a bundle-id name like `com.acme.app` says nothing about this on its own.
    var isDirectory: Bool = false

    var id: String { url.path }

    /// Tilde-abbreviated path, the form the list shows (`~/Library/Caches/com.acme.app`).
    var displayPath: String { (url.path as NSString).abbreviatingWithTildeInPath }
}

/// Discovery of the files an app leaves outside its bundle. Foundation-only and pure — every input
/// (home directory, sibling-install flag) is injected, so `Tools/leftovers-test.swift` can compile it
/// standalone and drive it against a throwaway home.
///
/// The policy is deliberately conservative: only the `~/Library` subtrees below are ever searched,
/// only exact bundle-id / app-name keyed children of those roots match, and every result is
/// re-verified to be a proper descendant of a known root before it is returned. Anything that would
/// widen a match beyond one app's own data belongs nowhere near this file.
enum AppLeftovers {

    // MARK: - Uninstall eligibility

    /// Whether the uninstall screen may open for an app at all. Apple's own apps are refused outright —
    /// the action doesn't appear for them — as is Tinycast itself, where uninstalling the running app
    /// from inside it has no sane outcome.
    ///
    /// Offering a screen on which nothing can be removed is worse than not offering it: it invites the
    /// user to try. Removability of the paths that *do* get listed is a separate, per-row question
    /// (`isRemovable`), for the third-party cases — a root-owned bundle, an immutable file.
    static func canUninstall(url: URL, bundleID: String?) -> Bool {
        let path = url.path
        guard path.hasSuffix(".app") else { return false }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") { return false }
        guard let bundleID else { return true }
        if isProtectedVendor(bundleID: bundleID) { return false }
        // Every channel of Tinycast (dev / beta / stable) shares this prefix.
        return bundleID != "com.tinycast.app" && !bundleID.hasPrefix("com.tinycast.app.")
    }

    /// Apps Tinycast never uninstalls: Apple's own. Their bundles are SIP-held and their support folders
    /// are system-managed, so a half-removed system app isn't a state a launcher should be able to create.
    static func isProtectedVendor(bundleID: String?) -> Bool {
        bundleID?.hasPrefix("com.apple.") == true
    }

    /// What a row needs to know about a path, from a single `lstat`: whether it can actually be removed
    /// (the parent must permit deletion — that is what protects `/System` and anything root owns — and the
    /// file must carry neither the immutable nor the SIP-restricted flag), and whether it is a directory.
    static func facts(for url: URL) -> (isRemovable: Bool, isDirectory: Bool) {
        var status = stat()
        guard lstat(url.path, &status) == 0 else { return (false, false) }
        let locked = UInt32(SF_RESTRICTED) | UInt32(SF_IMMUTABLE) | UInt32(UF_IMMUTABLE)
        let removable =
            status.st_flags & locked == 0
            && FileManager.default.isDeletableFile(atPath: url.path)
        return (removable, status.st_mode & S_IFMT == S_IFDIR)
    }

    /// Whether this path can actually be removed. Locked rows come from here.
    static func isRemovable(_ url: URL) -> Bool { facts(for: url).isRemovable }

    // MARK: - Discovery

    /// Every support path keyed by this app's bundle id or name. When `siblingBundleExists` (another
    /// install shares the bundle id, e.g. `Xcode.app` beside `Xcode-beta.app`) every keyed path could
    /// belong to the survivor, so all of them are dropped and only the bundle is offered.
    ///
    /// Returns paths only — sizes are measured by the caller, which owns the off-main walk.
    static func supportPaths(
        appName: String, bundleID: String?, home: URL, siblingBundleExists: Bool = false
    ) -> [URL] {
        let bundleID = validBundleID(bundleID)
        // With a surviving sibling the bundle id is shared, so nothing keyed on it is safely ours.
        let identifiers = siblingBundleExists ? [] : bundleID.map { [$0] } ?? []
        let names = siblingBundleExists ? [] : nameVariants(appName)

        var found: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL?) {
            guard let url, isSafeResult(url, home: home) else { return }
            let fm = FileManager.default
            guard fm.fileExists(atPath: url.path), seen.insert(url.path).inserted else { return }
            found.append(url)
        }

        for name in names {
            add(child(home, "Library/Application Support", name))
            add(child(home, "Library/Caches", name))
            add(child(home, "Library/Logs", name))
            add(child(home, "Library/Preferences", name + ".plist"))
            add(child(home, "Library/Saved Application State", name + ".savedState"))
        }

        for id in identifiers {
            add(child(home, "Library/Application Support", id))
            add(child(home, "Library/Application Scripts", id))
            add(child(home, "Library/Application Support/CrashReporter", id))
            add(child(home, "Library/Autosave Information", id))
            add(child(home, "Library/Caches", id))
            add(child(home, "Library/Caches/com.apple.nsurlsessiond/Downloads", id))
            add(child(home, "Library/Containers", id))
            add(child(home, "Library/Cookies", id + ".binarycookies"))
            add(child(home, "Library/HTTPStorages", id))
            add(child(home, "Library/HTTPStorages", id + ".binarycookies"))
            add(child(home, "Library/LaunchAgents", id + ".plist"))
            add(child(home, "Library/Logs", id))
            add(child(home, "Library/Preferences", id + ".plist"))
            add(child(home, "Library/Saved Application State", id + ".savedState"))
            add(child(home, "Library/SyncedPreferences", id + ".plist"))
            add(child(home, "Library/WebKit", id))
            add(child(home, "Library/WebKit/com.apple.WebKit.WebContent", id))

            // Helper bundles, XPC services and app extensions key their own data on ids derived from
            // the app's — `com.acme.app.helper` — so these roots match on a dotted-boundary prefix.
            for root in ["Library/Application Scripts", "Library/Containers", "Library/WebKit"] {
                for url in children(of: child(home, root), where: { $0.hasPrefix(id + ".") }) {
                    add(url)
                }
            }
            // Group containers are prefixed with the vendor's team id (`5HD2ARTBFS.com.acme.app`)
            // and can also be suffixed for a sub-group, so both boundaries count.
            for url in children(
                of: child(home, "Library/Group Containers"),
                where: { $0 == id || $0.hasSuffix("." + id) || $0.hasPrefix(id + ".") })
            {
                add(url)
            }
            // Per-host preferences carry a hardware UUID between the id and `.plist`.
            for url in children(
                of: child(home, "Library/Preferences/ByHost"),
                where: { $0.hasPrefix(id + ".") && $0.hasSuffix(".plist") })
            {
                add(url)
            }
            // Login-item and helper launch agents (`com.acme.app.updater.plist`).
            for url in children(
                of: child(home, "Library/LaunchAgents"),
                where: { $0.hasPrefix(id + ".") && $0.hasSuffix(".plist") })
            {
                add(url)
            }
        }

        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: - Guards

    /// The only subtrees a support path may live in. A result outside every root is dropped, so a
    /// malformed name or bundle id can never widen discovery beyond the user's own app data.
    private static let allowedRoots = [
        "Library/Application Scripts",
        "Library/Application Support",
        "Library/Autosave Information",
        "Library/Caches",
        "Library/Containers",
        "Library/Cookies",
        "Library/Group Containers",
        "Library/HTTPStorages",
        "Library/LaunchAgents",
        "Library/Logs",
        "Library/Preferences",
        "Library/Saved Application State",
        "Library/SyncedPreferences",
        "Library/WebKit",
    ]

    /// A result must be a *proper* descendant of an allowed root — never a root itself, never home,
    /// and never reachable by traversal (`..`) out of one.
    private static func isSafeResult(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard path != homePath, !path.contains("/../"), !path.hasSuffix("/..") else { return false }
        for root in allowedRoots {
            let rootPath = homePath + "/" + root
            if path == rootPath { return false }
            if path.hasPrefix(rootPath + "/") {
                // One more component at least, and it must not be empty (`…/Caches//`).
                return path.count > rootPath.count + 1
            }
        }
        return false
    }

    /// Bundle ids are used to build paths and prefix matches, so anything that isn't plain
    /// reverse-DNS is refused rather than sanitized: a path separator or glob metacharacter in a
    /// hand-edited `Info.plist` must not be able to reach outside a root or broaden a match.
    private static func validBundleID(_ bundleID: String?) -> String? {
        guard let bundleID, bundleID.count >= 3, bundleID.contains("."),
            !bundleID.hasPrefix("."), !bundleID.hasSuffix("."), !bundleID.contains("..")
        else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
            .union(CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"))
        guard bundleID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return bundleID
    }

    /// Naming variants an app might use for its support folders — "Maestro Studio" also writes
    /// "MaestroStudio", "Maestro-Studio", "Maestro_Studio". Short names are refused outright: a
    /// two-letter folder match is far more likely to be another app's data than this one's.
    private static func nameVariants(_ appName: String) -> [String] {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 3, !name.contains("/"), !name.contains(":") else { return [] }
        var variants = [name]
        if name.contains(" ") {
            for separator in ["", "-", "_"] {
                let variant = name.replacingOccurrences(of: " ", with: separator)
                if variant.count >= 3 { variants.append(variant) }
            }
        }
        var seen = Set<String>()
        return variants.filter { seen.insert($0).inserted }
    }

    /// A named child of a root, or nil when the name can't form one safely.
    private static func child(_ home: URL, _ root: String, _ name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { return nil }
        return home.appendingPathComponent(root).appendingPathComponent(name)
    }

    private static func child(_ home: URL, _ root: String) -> URL {
        home.appendingPathComponent(root)
    }

    /// Direct children of `root` whose last path component passes `predicate`. One flat listing, no
    /// recursion, and a missing or unreadable root yields nothing.
    private static func children(of root: URL, where predicate: (String) -> Bool) -> [URL] {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [])
        else { return [] }
        return items.filter { predicate($0.lastPathComponent) }
    }

    // MARK: - Sizing

    /// Bytes on disk for a file or directory tree, or nil when it can't be measured. Directories are
    /// walked with allocated sizes (what the user gets back), skipping nothing — this runs off-main.
    static func size(of url: URL) -> Int64? {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey,
            .isSymbolicLinkKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        // A symlink is reported as unmeasured, never followed: the link itself costs nothing worth
        // showing, and its target is not what removal takes — sizing through it would count a tree that
        // stays on disk (a cask's `/Applications` alias points at the same bundle already listed).
        guard values.isSymbolicLink != true else { return nil }
        guard values.isDirectory == true else { return allocatedSize(values) }

        var total: Int64 = 0
        // No `skipsHiddenFiles`: dotfiles inside a support folder are part of what gets removed.
        guard
            let walker = fm.enumerator(
                at: url, includingPropertiesForKeys: Array(keys), options: [])
        else { return nil }
        for case let child as URL in walker {
            guard let childValues = try? child.resourceValues(forKeys: keys) else { continue }
            total += allocatedSize(childValues) ?? 0
        }
        return total
    }

    private static func allocatedSize(_ values: URLResourceValues) -> Int64? {
        if let allocated = values.totalFileAllocatedSize { return Int64(allocated) }
        if let allocated = values.fileAllocatedSize { return Int64(allocated) }
        return nil
    }

    // MARK: - Removal

    /// Removes each path and returns the ones that failed, keyed by path. One item failing never stops
    /// the rest — a root-owned bundle shouldn't leave the support files it came with behind.
    ///
    /// `permanently` unlinks; the default trashes, which is what the ↵ / footer path uses so a
    /// fully-checked list stays recoverable. Lives here (not in `UninstallSession`) so
    /// `Tools/leftovers-test.swift` can drive it against throwaway fixtures.
    static func remove(_ urls: [URL], permanently: Bool) -> Set<String> {
        var failed = Set<String>()
        for url in urls {
            do {
                if permanently {
                    try FileManager.default.removeItem(at: url)
                } else {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
            } catch {
                failed.insert(url.path)
            }
        }
        return failed
    }
}
