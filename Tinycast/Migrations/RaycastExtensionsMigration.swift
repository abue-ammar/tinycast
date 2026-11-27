import Foundation

/// Clears what the removed Raycast extension runtime left behind, on this Mac and in iCloud.
enum RaycastExtensionsMigration {
    static let retiredDefaults: Set<String> = [
        "extensionsEnabled", "extensionsShowInLauncher", "extensionPackageManager",
        "extensionCustomSearchPaths", "extensionAppearances", "boundExtensionCommandEntryIDs"
    ]
    static let retiredFiles = [
        "extensions", "extension-data", "extension-support", "extension-commands.json",
        "extension-versions.json"
    ]

    /// Defaults and `settings.json` now; the files off-main, as an extension can hold thousands.
    static func run(defaults: UserDefaults, supportDirectory: URL, settingsFile: URL?) {
        for key in defaults.dictionaryRepresentation().keys where isRetiredDefault(key) {
            defaults.removeObject(forKey: key)
        }
        if let settingsFile, let data = try? Data(contentsOf: settingsFile),
            let stripped = strippingRetiredSection(data)
        {
            try? stripped.write(to: settingsFile.resolvingSymlinksInPath(), options: .atomic)
        }
        Task.detached(priority: .utility) { removeFiles(in: supportDirectory) }
    }

    /// Nil when the section is absent or the file has other problems, which the import must report.
    static func strippingRetiredSection(_ data: Data) -> Data? {
        guard let parsed = try? SettingsFileFormat.parse(data),
            parsed.issues == [.unknownSetting("extensions")]
        else { return nil }
        return SettingsFileFormat.render(parsed.values)
    }

    static func isRetiredDefault(_ key: String) -> Bool {
        retiredDefaults.contains(key) || key.hasPrefix("hotkey.extensionCommand.")
            || (key.hasPrefix("NSStatusItem ") && key.contains(" extension:"))
    }

    nonisolated static func removeFiles(in supportDirectory: URL) {
        for name in retiredFiles {
            try? FileManager.default.removeItem(at: supportDirectory.appending(path: name))
        }
    }

    /// The launcher keys an extension command left in favorites, aliases, hidden items and ranking.
    static func retiredEntries(in lists: [String]...) -> Set<String> {
        Set(lists.joined().filter { $0.hasPrefix("extension:") })
    }

    /// Every record the runtime synced is named after its source, `extensions`, but its one setting.
    static func isRetiredRecord(_ recordName: String) -> Bool {
        recordName.hasPrefix("extensions.") || recordName == retiredSettingRecord
    }

    private static let retiredSettingRecord = SyncSourceID.settings.recordName(
        for: "extensions.showInLauncher")
}
