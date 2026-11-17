import Foundation

/// Every settings.json binding, built once and shared by the settings file and iCloud Sync.
@MainActor
struct SettingsBindingSet {
    let bindings: [SettingsFileBinding]
    let commit: () -> [SettingsFileIssue]
    /// Kept to apply a waiting launcher record once its app is installed.
    let launcher: LauncherSettingsFile
}
