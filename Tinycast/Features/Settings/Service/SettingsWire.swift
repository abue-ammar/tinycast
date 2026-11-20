import Foundation

/// What the main app and Settings' own process say to each other over their link.
enum SettingsWire {
    enum ToSettings: Codable, Sendable {
        case show(SettingsRequest)
        case changed(SharedChange)
        case status(MainAppStatus)
        case callEvent(UUID, ExtensionCallEvent)
        case mcpResult(UUID, MCPSettingsResult)
    }

    enum ToMainApp: Codable, Sendable {
        case changed(SharedChange)
        /// Sent at once, never debounced: the main app's shortcuts go quiet before a key lands.
        case recordingShortcut(Bool)
        case perform(SettingsAction)
        /// Awaited by the pane: an extension change reports progress and ends with a result.
        case call(UUID, ExtensionCall)
        case mcpCall(UUID, MCPSettingsCall)
        case cancelCall(UUID)
        /// LaunchServices may hand either instance a link; only the main app acts on one.
        case openURL(URL)
        /// The window is up; macOS lets only the app the user just addressed bring it forward.
        case activate
    }
}

enum MCPSettingsCall: Codable, Sendable {
    case signIn(MCPServer, MCPOAuth.Credentials)
    case signOut(UUID)
    case test(MCPServer, MCPSecretStore.Secrets)
    case save(MCPServer, MCPSecretStore.Secrets)
    case remove(UUID)
}

enum MCPSettingsResult: Codable, Sendable {
    case success(MCPServerStatus? = nil)
    case failure(String)
    case cancelled

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    func get() throws -> MCPServerStatus? {
        switch self {
        case .success(let status): return status
        case .failure(let message): throw Failure(errorDescription: message)
        case .cancelled: throw CancellationError()
        }
    }
}
