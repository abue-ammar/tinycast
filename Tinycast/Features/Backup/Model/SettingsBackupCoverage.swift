import Foundation

/// What `SettingsBackup.SettingsData` carries, written out so a new setting has to be considered.
enum SettingsBackupCoverage {
    /// Each `SettingsData` field paired with the `AppSettings` key it mirrors.
    static let mirrored: [String: AppSettingsKey] = [
        "clipboardRetentionDays": .clipboardRetention,
        "clipboardDisabledApps": .clipboardDisabledApps,
        "hyperKey": .hyperKey,
        "hyperKeyIncludesShift": .hyperKeyIncludesShift,
        "hyperKeyQuickPress": .hyperKeyQuickPress,
        "emojiSkinTone": .emojiSkinTone,
        "popToRootSeconds": .popToRootTimeout,
        "compactMode": .compactMode,
        "showFavoritesInCompactMode": .showFavoritesInCompactMode,
        "searchScopes": .searchScopes,
        "openOnCursorScreen": .openOnCursorScreen,
        "customCommandsEnabled": .customCommandsEnabled,
        "customCommandsShowInLauncher": .customCommandsShowInLauncher,
        "snippetsShowInLauncher": .snippetsShowInLauncher,
        "windowManagementEnabled": .windowManagementEnabled,
        "windowManagementShowInLauncher": .windowManagementShowInLauncher,
        "windowGap": .windowGap,
        "windowCycleOnRepeat": .windowCycleOnRepeat,
        "quicklinksEnabled": .quicklinksEnabled,
        "quicklinksShowInLauncher": .quicklinksShowInLauncher,
        "quicklinkOpensNewWindow": .quicklinkOpensNewWindow,
        "quicklinkSelectionFallback": .quicklinkSelectionFallback,
        "quicklinkConfirmsBeforeDelete": .quicklinkConfirmsBeforeDelete
    ]

    /// The `SettingsData` fields no `AppSettings` key stands behind, and what they read instead.
    static let externallySourced: [String: String] = [
        "launchAtLogin": "Read from LaunchAtLogin, which owns the login item, not UserDefaults.",
        "showInMenuBar": "SettingsKey.showInMenuBar — shared with MenuBarExtra, not owned here."
    ]

    /// Keys kept out of a backup on purpose, each with the reason it has to stay out.
    static let deliberatelyExcluded: [String: String] = [
        AppSettingsKey.snippetsEnabled.rawValue:
            "Doubles as keyword-expansion consent; an import must not enable keystroke listening."
    ]
}
