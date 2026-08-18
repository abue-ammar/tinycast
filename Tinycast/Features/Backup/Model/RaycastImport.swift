import Foundation

/// Reads a `.rayconfig`, dispatching on format. See docs/features/raycast-import.md.
enum RaycastImport {
    struct Result {
        var backup: SettingsBackup
        var clipboard: [ClipboardItem]
        var snippets: [Snippet]
        /// Image clips whose file no longer exists, reported so the UI can note them.
        var missingImages: Int

        /// Trimmed to the chosen categories; `apply()` being per-field, dropping is enough.
        func selecting(_ options: RaycastImportOptions) -> Result {
            var trimmed = SettingsBackup()
            if options.contains(.shortcuts) { trimmed.hotkeys = backup.hotkeys }
            if options.contains(.favorites) { trimmed.favoriteApps = backup.favoriteApps }
            if options.contains(.aliases) { trimmed.launcherAliases = backup.launcherAliases }

            var settings = SettingsBackup.SettingsData()
            var hasSettings = false
            if options.contains(.emojiSkinTone), let tone = backup.settings?.emojiSkinTone {
                settings.emojiSkinTone = tone
                hasSettings = true
            }
            if options.contains(.launchAtLogin), let launch = backup.settings?.launchAtLogin {
                settings.launchAtLogin = launch
                hasSettings = true
            }
            if options.contains(.menuBarVisibility), let show = backup.settings?.showInMenuBar {
                settings.showInMenuBar = show
                hasSettings = true
            }
            if options.contains(.popToRoot), let secs = backup.settings?.popToRootSeconds {
                settings.popToRootSeconds = secs
                hasSettings = true
            }
            if options.contains(.compactMode) {
                if let compact = backup.settings?.compactMode {
                    settings.compactMode = compact
                    hasSettings = true
                }
                if let showFavorites = backup.settings?.showFavoritesInCompactMode {
                    settings.showFavoritesInCompactMode = showFavorites
                    hasSettings = true
                }
            }
            if options.contains(.shortcuts) {
                if let shift = backup.settings?.hyperKeyIncludesShift {
                    settings.hyperKeyIncludesShift = shift
                    hasSettings = true
                }
                if let key = backup.settings?.hyperKey {
                    settings.hyperKey = key
                    hasSettings = true
                }
            }

            let keepClipboard = options.contains(.clipboardHistory)
            // The per-app exclusion list belongs to clipboard history, not to settings as a whole.
            if keepClipboard, let disabled = backup.settings?.clipboardDisabledApps {
                settings.clipboardDisabledApps = disabled
                hasSettings = true
            }
            if hasSettings { trimmed.settings = settings }

            return Result(
                backup: trimmed,
                clipboard: keepClipboard ? clipboard : [],
                snippets: options.contains(.snippets) ? snippets : [],
                missingImages: keepClipboard ? missingImages : 0)
        }
    }

    static func read(file: URL, passphrase: String) throws -> Result {
        let raw = try Data(contentsOf: file)
        switch try RaycastFormat.detect(raw) {
        case .v1: return try RaycastImportV1.read(raw, passphrase: passphrase)
        case .v2: return try RaycastImportV2.read(raw, passphrase: passphrase)
        }
    }
}
