import Foundation

/// Everything in Tinycast a global shortcut can be bound to.
enum HotKeyAction: Hashable, Sendable {
    case togglePalette
    case toggleClipboard
    case toggleEmoji
    case searchFiles
    case app(bundleID: String)
    case settingsPane(bundleID: String)
    case customCommand(id: UUID)
    case systemAction(id: SystemAction.ID)
    case windowCommand(id: WindowCommand.ID)
    case quicklink(id: UUID)

    /// The UserDefaults key, and the `HotKeyCenter` registration id: one per action.
    var defaultsKey: String {
        switch self {
        case .togglePalette: "hotkey.togglePalette"
        case .toggleClipboard: "hotkey.toggleClipboard"
        case .toggleEmoji: "hotkey.toggleEmoji"
        case .searchFiles: "hotkey.searchFiles"
        case .app(let bundleID): "hotkey.app." + bundleID
        case .settingsPane(let bundleID): "hotkey.pane." + bundleID
        case .customCommand(let id): "hotkey.customCommand." + id.uuidString.lowercased()
        case .systemAction(let id): "hotkey.systemAction." + id.rawValue
        case .windowCommand(let id): "hotkey.windowCommand." + id.rawValue
        case .quicklink(let id): "hotkey.quicklink." + id.uuidString.lowercased()
        }
    }
}
