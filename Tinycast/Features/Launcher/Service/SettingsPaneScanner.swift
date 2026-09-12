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
        fileprivate let languages: [String]
        fileprivate let panes: [AppEntry]
    }

    /// All Settings panes, sorted by display name.
    nonisolated static func scan(languages: [String], cache: Cache?) -> ([AppEntry], Cache?) {
        let fm = FileManager.default
        let modified = try? extensionsDir.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        if let cache, cache.modified == modified, cache.languages == languages {
            return (cache.panes, cache)
        }
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
                let base = AppDisplayName.inInfo(info)
            else { continue }
            let names = BundleLocalization.names(
                for: url, base: base,
                developmentRegion: info["CFBundleDevelopmentRegion"] as? String,
                languages: languages)
            result.append(
                AppEntry(
                    id: url.path, name: nameOverrides[bundleID] ?? names.first ?? base, url: url,
                    bundleID: bundleID, kind: .systemSettings,
                    // `EntryNaming` drops whatever repeats the name, so the whole list can go in.
                    alternateNames: names))
        }
        let panes = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return (panes, modified.map { Cache(modified: $0, languages: languages, panes: panes) })
    }

    private static func isSettingsPane(info: [String: Any]) -> Bool {
        let ex = (info["EXAppExtensionAttributes"] as? [String: Any])?["EXExtensionPointIdentifier"]
        if ex as? String == settingsExtensionPoint { return true }
        let ns = (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"]
        return ns as? String == settingsExtensionPoint
    }

    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil))
            as? [String: Any]
    }
}
