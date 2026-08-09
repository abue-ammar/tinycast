import Foundation

/// Enumerates the System Settings panes into launchable entries, off the main actor.
enum SettingsPaneScanner {
    private static let extensionsDir = URL(
        fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
    private static let settingsExtensionPoint = "com.apple.Settings.extension.ui"

    /// Panes whose bundle carries a junk or missing display name; keyed by CFBundleIdentifier.
    private static let nameOverrides: [String: String] = [
        "com.apple.Battery-Settings.extension": "Battery",
        "com.apple.HeadphoneSettings": "Headphones"
    ]

    /// Panes that shouldn't appear in the launcher at all (contextual/one-shot panes).
    private static let skippedBundleIDs: Set<String> = []

    /// Panes change only on an OS update, and an unreadable listing or date is never cached.
    struct Cache: Sendable {
        fileprivate let modified: Date
        fileprivate let panes: [AppEntry]
    }

    /// All Settings panes, sorted by display name.
    nonisolated static func scan(cache: Cache?) -> ([AppEntry], Cache?) {
        let fm = FileManager.default
        let modified = try? extensionsDir.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let cache, cache.modified == modified { return (cache.panes, cache) }
        guard
            let items = try? fm.contentsOfDirectory(
                at: extensionsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return ([], nil) }

        var result: [AppEntry] = []
        for url in items where url.pathExtension == "appex" {
            guard
                let info = plist(at: url.appendingPathComponent("Contents/Info.plist")),
                isSettingsPane(info: info),
                let bundleID = info["CFBundleIdentifier"] as? String,
                !skippedBundleIDs.contains(bundleID),
                let name = displayName(appexURL: url, info: info, bundleID: bundleID)
            else { continue }
            result.append(
                AppEntry(
                    id: url.path, name: name, url: url, bundleID: bundleID,
                    kind: .systemSettings))
        }
        let panes = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return (panes, modified.map { Cache(modified: $0, panes: panes) })
    }

    private static func isSettingsPane(info: [String: Any]) -> Bool {
        let ex = (info["EXAppExtensionAttributes"] as? [String: Any])?["EXExtensionPointIdentifier"]
        if ex as? String == settingsExtensionPoint { return true }
        let ns = (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"]
        return ns as? String == settingsExtensionPoint
    }

    /// Overrides, then loctable, then Info.plist; nil skips the pane entirely.
    private static func displayName(
        appexURL: URL, info: [String: Any], bundleID: String
    ) -> String? {
        if let override = nameOverrides[bundleID] { return override }
        if let localized = loctableName(appexURL: appexURL) { return localized }
        return (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
    }

    /// Localized name from `InfoPlist.loctable`, preferred languages first, then English.
    private static func loctableName(appexURL: URL) -> String? {
        let url = appexURL.appendingPathComponent("Contents/Resources/InfoPlist.loctable")
        guard let table = plist(at: url) else { return nil }
        var codes = Locale.preferredLanguages.flatMap { tag -> [String] in
            // loctable keys use underscores where language tags use hyphens.
            let underscored = tag.replacingOccurrences(of: "-", with: "_")
            let bare = tag.split(separator: "-").first.map(String.init)
            return ([underscored, bare].compactMap { $0 }).filter { !$0.isEmpty }
        }
        codes.append("en")
        for code in codes {
            if let entry = table[code] as? [String: Any],
                let name = entry["CFBundleDisplayName"] as? String
            {
                return name
            }
        }
        return nil
    }

    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil))
            as? [String: Any]
    }
}
