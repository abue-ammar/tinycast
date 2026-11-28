import Foundation

/// Clears what the removed Raycast extension runtime left behind, on this Mac and in iCloud.
enum RaycastExtensionsMigration {
    static let retiredDefaults: Set<String> = [
        "extensionsShowInLauncher", "extensionPackageManager",
        "extensionCustomSearchPaths", "extensionAppearances", "boundExtensionCommandEntryIDs"
    ]
    /// Every launcher key the runtime wrote; native extension commands use `extension-command:`.
    static let retiredEntryPrefix = "extension:"
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
            let stripped = strippingRetiredKey(data)
        {
            try? stripped.write(to: settingsFile.resolvingSymlinksInPath(), options: .atomic)
        }
        Task.detached(priority: .utility) { removeFiles(in: supportDirectory) }
    }

    /// Nil when the key is absent or the file has other problems, which the import must report.
    static func strippingRetiredKey(_ data: Data) -> Data? {
        guard let parsed = try? SettingsFileFormat.parse(data),
            parsed.issues == [.unknownSetting(retiredSettingsFileKey)]
        else { return nil }
        return SettingsFileFormat.render(parsed.values)
    }

    static func isRetiredDefault(_ key: String) -> Bool {
        retiredDefaults.contains(key) || key.hasPrefix("hotkey.extensionCommand." + retiredEntryPrefix)
            || (key.hasPrefix("NSStatusItem ") && key.contains(" " + retiredEntryPrefix))
    }

    nonisolated static func removeFiles(in supportDirectory: URL) {
        for name in retiredFiles {
            try? FileManager.default.removeItem(at: supportDirectory.appending(path: name))
        }
    }

    /// The launcher keys an extension command left in favorites, aliases, hidden items and ranking.
    static func retiredEntries(in lists: [String]...) -> Set<String> {
        Set(lists.joined().filter { $0.hasPrefix(retiredEntryPrefix) })
    }

    /// Every record the runtime synced is named after its source, `extensions`, but its one setting.
    static func isRetiredRecord(_ recordName: String) -> Bool {
        recordName.hasPrefix("extensions.") || recordName == retiredSettingRecord
    }

    /// Its commands' aliases and chords rode the shared shortcut source, known only by their key.
    static func isRetiredEntry(_ source: SyncSourceID, key: String) -> Bool {
        source == .launcherShortcuts && key.hasPrefix(retiredEntryPrefix)
    }

    /// Native extensions own the `extensions` section now, so only the old runtime's key goes.
    private static let retiredSettingsFileKey = "extensions.showInLauncher"
    private static let retiredSettingRecord = SyncSourceID.settings.recordName(for: retiredSettingsFileKey)
}
