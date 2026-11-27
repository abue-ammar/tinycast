import Foundation

/// What only the main app knows, mirrored into Settings' process for its panes to show.
struct MainAppStatus: Codable, Equatable, Sendable {
    struct HyperKey: Codable, Equatable, Sendable {
        var status: HyperKeyManager.Status = .off
        var route: HyperKeyRoute?
        /// Read on demand, as the main app's own pane did: a takeover leaves nothing to observe.
        var takeover: HyperKeyDiagnostics.Takeover?
        var diagnostics: HyperKeyDiagnostics?
    }

    struct CloudSync: Codable, Equatable, Sendable {
        var status: CloudSyncStatus = .off
        var stopReason: CloudSyncStopReason?
        var counts: [SyncCategory: CloudSyncCoordinator.Counts] = [:]
        var thisMac = ""
        var otherDevices: [SyncDevice] = []
    }

    struct DictationModels: Codable, Equatable, Sendable {
        var installed: Set<DictationModel> = []
        var downloading: DictationModel?
        var received: Int64?
        var total: Int64?
        var removing: DictationModel?
        var transcribing = false

        var downloadProgress: (received: Int64, total: Int64)? {
            guard let received, let total else { return nil }
            return (received, total)
        }

        func isInstalled(_ model: DictationModel) -> Bool { installed.contains(model) }
    }

    struct Updates: Codable, Equatable, Sendable {
        var updatesItself = false
        var isChecking = false
        var lastCheckedAt: Date?
        var availableVersion: String?
    }

    var hiddenCommands: Set<CommandID> = []
    var unlistedCommands: Set<CommandID> = []
    var launcherRankingIsEmpty = true
    var hyperKey = HyperKey()
    var modifierTapsNeedAccessibility = false
    var snippetsNeedAccessibility = false
    var fileIndex: FileIndexer.Status = .off
    var cloudSync = CloudSync()
    var dictationModels = DictationModels()
    var mcpStatuses: [UUID: MCPServerStatus] = [:]
    var mcpAuthentication: [UUID: MCPOAuthManager.Status] = [:]
    var updates = Updates()
}
