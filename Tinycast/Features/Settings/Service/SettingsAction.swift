import Foundation

/// Work a pane asks of the main app, because the engine or surface it needs runs only there.
enum SettingsAction: Codable, Sendable {
    case resetLauncherRanking
    case inspectHyperKey(diagnostics: Bool)
    case restartHyperKey
    case setICloudSyncEnabled(Bool)
    case setICloudSyncIncluded(SyncCategory, Bool)
    case refreshICloudSync
    case renameThisMac(String)
    case removeSyncDevice(String)
    case deleteICloudData
    case editCustomCommand(UUID?)
    case editQuicklink(UUID?)
    case editSnippet(StoredSnippet.ID?)
    case createRoom
    case editRoomWindows(UUID)
    case enterRoom(UUID)
    case runWindowLayout(UUID)
    case clearClipboardHistory
    case rebuildFileIndex
    case refreshFileAccess
    case reloadCalendar
    case downloadDictationModel(DictationModel)
    case removeDictationModel(DictationModel)
    case cancelDictationDownload
    case refreshDictationModels
    case refreshInstalledAI(InstalledAIKind)
    case installedAILaunchChanged(InstalledAIKind)
    case discardUnsavedMCPServer(UUID)
    case setSettingsFile(SettingsFileChange)
    case setExtensionAppearance(String, ExtensionAppearance?)
    case setExtensionBackground(ExtensionCommandRef, Bool)
    case setExtensionMenuBar(ExtensionCommandRef, Bool)
    case setExtensionPreference(String, key: String, ExtensionPreferenceValue?)
    /// After an import in Settings: what the main app holds in memory is read from disk again.
    case reloadImportedData
    case checkForUpdates
    case showSupport
}

/// What the Backup pane decided about the settings file, after asking in its own window.
enum SettingsFileChange: Codable, Sendable {
    case stop
    case start(importing: Bool)
}
