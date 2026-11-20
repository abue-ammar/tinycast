import Foundation

/// What the main app and Settings' own process say to each other over their link.
enum SettingsWire {
    enum ToSettings: Codable, Sendable {
        case show(SettingsRequest)
        case changed(SharedChange)
        case status(MainAppStatus)
        case callEvent(UUID, ExtensionCallEvent)
    }

    enum ToMainApp: Codable, Sendable {
        case changed(SharedChange)
        /// Sent at once, never debounced: the main app's shortcuts go quiet before a key lands.
        case recordingShortcut(Bool)
        case perform(SettingsAction)
        /// Awaited by the pane: an extension change reports progress and ends with a result.
        case call(UUID, ExtensionCall)
        case cancelCall(UUID)
        /// LaunchServices may hand either instance a link; only the main app acts on one.
        case openURL(URL)
        /// The window is up; macOS lets only the app the user just addressed bring it forward.
        case activate
    }
}
