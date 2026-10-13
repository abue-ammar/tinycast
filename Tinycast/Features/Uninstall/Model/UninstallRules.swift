import Foundation

/// Which directory entries belong to an app, from names alone. See docs/features/uninstall.md.
enum UninstallRules {
    /// Stripped before matching, so `com.foo.Bar.plist` compares as `com.foo.Bar`.
    static let strippedExtensions: Set<String> = [
        "plist", "savedstate", "binarycookies", "lockfile", "lock", "sfl", "sfl2", "sfl3",
        // Plug-in wrappers, named after the product that installed them.
        "qlgenerator", "saver", "prefpane", "service", "workflow", "mdimporter", "appex",
        "component", "wdgt", "dext", "driver"
    ]

    /// The name plus each stripped form; stripping only adds comparisons, never removes one.
    static func matchableForms(_ name: String) -> [String] {
        var forms = [name]
        var current = name
        for _ in 0..<3 {
            let ext = (current as NSString).pathExtension.lowercased()
            guard !ext.isEmpty, strippedExtensions.contains(ext) else { break }
            let stripped = (current as NSString).deletingPathExtension
            guard !stripped.isEmpty else { break }
            forms.append(stripped)
            current = stripped
        }
        return forms
    }

    /// `-` counts: vendors name variants that way, unless the variant is itself installed.
    private static let namespaceSeparators: Set<Character> = [".", "-"]

    /// The bundle ID itself, or a namespaced child of it.
    static func matchesBundleID(_ component: String, identity: UninstallIdentity) -> Bool {
        guard let id = identity.bundleID else { return false }
        return matchableForms(component).contains { form in
            let folded = UninstallIdentity.folded(form)
            guard owns(folded, id: id, allowingPrefix: identity.allowsBundleIDPrefixMatch)
            else { return false }
            // A longer-ID sibling owns its own artifacts, so channels can't claim each other.
            return !identity.otherBundleIDs.contains { other in
                other.count > id.count && owns(folded, id: other, allowingPrefix: true)
            }
        }
    }

    private static func owns(_ folded: String, id: String, allowingPrefix: Bool) -> Bool {
        if folded == id { return true }
        guard allowingPrefix, folded.count > id.count, folded.hasPrefix(id) else { return false }
        // The separator stops an ID that merely shares a prefix reading as this one's child.
        return namespaceSeparators.contains(folded[folded.index(folded.startIndex, offsetBy: id.count)])
    }

    /// Attribution by link target, never by name — the name is whatever the vendor chose.
    static func isBundleSymlink(target: String, bundlePath: String) -> Bool {
        let target = (target as NSString).standardizingPath
        let bundlePath = (bundlePath as NSString).standardizingPath
        return target == bundlePath || isDescendant(target, of: bundlePath)
    }

    /// Strips a leading `group.` and/or Team ID; the strict 10-char shape stops false hits.
    static func groupContainerBase(_ component: String) -> String {
        var base = component
        for _ in 0..<2 {
            if base.lowercased().hasPrefix("group.") {
                base = String(base.dropFirst("group.".count))
                continue
            }
            guard let dot = base.firstIndex(of: "."), isTeamID(String(base[base.startIndex..<dot]))
            else { break }
            base = String(base[base.index(after: dot)...])
        }
        return base
    }

    static func isTeamID(_ value: String) -> Bool {
        value.count == 10
            && value.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) && !$0.isLowercase }
    }

    static func matchesGroupContainer(_ component: String, identity: UninstallIdentity) -> Bool {
        matchesBundleID(groupContainerBase(component), identity: identity)
    }

    /// Exact folded equality: no prefix, no substring, so "Foo" can't claim "Foo Bar".
    static func matchesDisplayName(_ component: String, identity: UninstallIdentity) -> Bool {
        guard !identity.names.isEmpty else { return false }
        return matchableForms(component).contains { form in
            identity.names.contains(UninstallIdentity.folded(form))
        }
    }

    static func evidence(
        for name: String, in root: UninstallSearchRoot, identity: UninstallIdentity
    ) -> UninstallEvidence? {
        if root.styles.contains(.bundleID), matchesBundleID(name, identity: identity) {
            return .bundleID
        }
        if root.styles.contains(.groupContainer), matchesGroupContainer(name, identity: identity) {
            return .groupContainer
        }
        if root.styles.contains(.displayName), matchesDisplayName(name, identity: identity) {
            return .displayName
        }
        return nil
    }

    static func matches(
        childNames: [String], in root: UninstallSearchRoot, identity: UninstallIdentity
    ) -> [(name: String, evidence: UninstallEvidence)] {
        childNames.compactMap { name in
            evidence(for: name, in: root, identity: identity).map { (name, $0) }
        }
    }

    static func isAcceptableCandidate(
        path: String, rootPath: String, home: String, bundlePath: String
    ) -> Bool {
        let path = (path as NSString).standardizingPath
        let home = (home as NSString).standardizingPath
        let bundlePath = (bundlePath as NSString).standardizingPath
        guard path.hasPrefix("/"), path != "/", path != home, path != rootPath else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains("."), !components.contains("..")
        else { return false }
        guard (path as NSString).deletingLastPathComponent == rootPath else { return false }
        guard path != bundlePath, !isDescendant(path, of: bundlePath),
            !isDescendant(bundlePath, of: path)
        else { return false }
        return true
    }

    static func isDescendant(_ path: String, of ancestor: String) -> Bool {
        path.hasPrefix(ancestor + "/")
    }

    /// Takes `home` rather than reading it, so it stays pure.
    static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        guard isDescendant(path, of: home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
