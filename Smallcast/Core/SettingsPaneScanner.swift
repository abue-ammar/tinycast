import Foundation

/// Enumerates the System Settings panes (the `.appex` bundles behind each) into launchable `AppEntry` values, off the main actor inside `AppIndex.scan()`.
enum SettingsPaneScanner {
    private static let extensionsDir = URL(
        fileURLWithPath: "/System/Library/ExtensionKit/Extensions")
    private static let settingsExtensionPoint = "com.apple.Settings.extension.ui"

    /// Panes whose bundle carries a junk or missing display name; keyed by CFBundleIdentifier.
    private static let nameOverrides: [String: String] = [
        "com.apple.Battery-Settings.extension": "Battery",
        "com.apple.HeadphoneSettings": "Headphones",
    ]

    /// Panes that shouldn't appear in the launcher at all (contextual/one-shot panes).
    private static let skippedBundleIDs: Set<String> = []

    /// All Settings panes, sorted by display name.
    nonisolated static func scan() -> [AppEntry] {
        let fm = FileManager.default
        guard
            let items = try? fm.contentsOfDirectory(
                at: extensionsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }

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
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func isSettingsPane(info: [String: Any]) -> Bool {
        let ex = (info["EXAppExtensionAttributes"] as? [String: Any])?["EXExtensionPointIdentifier"]
        if ex as? String == settingsExtensionPoint { return true }
        let ns = (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"]
        return ns as? String == settingsExtensionPoint
    }

    /// Override table → localized loctable name → Info.plist names, returning `nil` (skip the pane) when nothing usable is found.
    private static func displayName(
        appexURL: URL, info: [String: Any], bundleID: String
    ) -> String? {
        if let override = nameOverrides[bundleID] { return override }
        if let localized = loctableName(appexURL: appexURL) { return localized }
        return (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String)
    }

    /// Localized `CFBundleDisplayName` from `InfoPlist.loctable` (keyed by locale), trying the user's preferred languages then English.
    private static func loctableName(appexURL: URL) -> String? {
        let url = appexURL.appendingPathComponent("Contents/Resources/InfoPlist.loctable")
        guard let table = plist(at: url) else { return nil }
        var codes = Locale.preferredLanguages.flatMap { tag -> [String] in
            // loctable keys use underscores ("en_AU") where language tags use hyphens ("en-AU"); try the underscored tag, then the bare code ("en").
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
