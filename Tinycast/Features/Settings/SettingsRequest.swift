import Foundation

/// One ask to show Settings; it crosses to Settings' own process, so it is plain data.
struct SettingsRequest: Codable, Sendable {
    /// Nil only reveals the window, so re-opening a minimised one keeps the pane it was on.
    var tab: SettingsTab?
    var target: SettingsTarget?
    var handoff: SettingsHandoff?
}

/// Work a pane picks up as it opens, started from outside Settings.
enum SettingsHandoff: Codable, Sendable {
    case editWindowLayout(WindowLayoutEditRequest)
    case installFromStore(ExtensionDeepLink.StoreInstall)
}
