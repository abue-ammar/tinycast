import Foundation

/// What the main app and Settings' own process say to each other over their link.
enum SettingsWire {
    enum ToSettings: Codable, Sendable {
        case show(UUID, SettingsRequest)
        case changed(SharedChange)
        case status(MainAppStatus)
        case extensionProgress(UUID, ExtensionCallEvent)
        case reply(UUID, Reply)
        case readyToClose
    }

    enum ToMainApp: Codable, Sendable {
        case changed(SharedChange)
        /// Sent at once, never debounced: the main app's shortcuts go quiet before a key lands.
        case recordingShortcut(Bool)
        case perform(SettingsAction)
        case call(UUID, Call)
        case cancelCall(UUID)
        /// LaunchServices may hand either instance a link; only the main app acts on one.
        case openURL(URL)
        /// The window is up; macOS lets only the app the user just addressed bring it forward.
        case activate(UUID)
        case closing
    }

    enum Call: Codable, Sendable {
        case extensions(ExtensionCall)
        case mcp(MCPSettingsCall)
        case backup(BackupSettingsCall)
    }

    enum Reply: Codable, Sendable {
        case extensions(ExtensionCallResult)
        case mcp(MCPServerStatus?)
        case backupPreview(BackupPreview)
        case backupMessage(String)
        case failure(String)
        case cancelled
    }

    struct Failure: LocalizedError {
        let errorDescription: String?

        static var disconnected: Self {
            Self(errorDescription: String(localized: "Lost the connection to Tinycast."))
        }
    }
}

enum MCPSettingsCall: Codable, Sendable {
    case signIn(MCPServer, MCPOAuth.Credentials)
    case signOut(UUID)
    case test(MCPServer, MCPSecretStore.Secrets)
    case save(MCPServer, MCPSecretStore.Secrets)
    case remove(UUID)
}

enum BackupSettingsCall: Codable, Sendable {
    case prepare(URL)
    case apply(UUID, Set<BackupCategory>)
    case export(URL, Set<BackupCategory>)
    case importRaycast(URL, passphrase: String, options: RaycastImportOptions)
}

struct BackupPreview: Codable, Sendable {
    let id: UUID
    let manifest: BackupManifest
    let customCommands: Int
    let globalShortcuts: Int
}
