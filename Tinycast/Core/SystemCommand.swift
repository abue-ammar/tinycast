import Foundation

struct SystemCommand: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case lockScreen = "lock-screen"
        case sleep
        case sleepDisplays = "sleep-displays"
        case restart
        case shutDown = "shut-down"
        case logOut = "log-out"
        case showScreenSaver = "show-screen-saver"
        case playPause = "play-pause"
        case nextTrack = "next-track"
        case previousTrack = "previous-track"
        case toggleMute = "toggle-mute"
        case volumeUp = "volume-up"
        case volumeDown = "volume-down"
        case setVolume = "set-volume"
        case volume0 = "volume-0"
        case volume25 = "volume-25"
        case volume50 = "volume-50"
        case volume75 = "volume-75"
        case volume100 = "volume-100"
        case showDesktop = "show-desktop"
        case toggleAppearance = "toggle-system-appearance"
        case toggleStageManager = "toggle-stage-manager"
        case openTrash = "open-trash"
        case emptyTrash = "empty-trash"
        case ejectAllDisks = "eject-all-disks"
        case toggleHiddenFiles = "toggle-hidden-files"
        case hideOtherApps = "hide-all-apps-except-frontmost"
        case unhideAllApps = "unhide-all-hidden-apps"
        case quitAllApps = "quit-all-apps"
        case dismissNotifications = "dismiss-notifications"
        case toggleBluetooth = "toggle-bluetooth"
    }

    enum Confirmation: String, Sendable {
        case none
        case required
    }

    let id: ID
    let name: String
    let sfSymbol: String
    let confirmation: Confirmation

    var entryID: String {
        // Preserve the existing Quit All launcher's persisted favorite, visibility and ranking key.
        id == .quitAllApps ? "command:quit-all-apps" : "system-command:" + id.rawValue
    }
}

enum SystemCommandCatalog {
    static let all: [SystemCommand] = SystemCommand.ID.allCases.map { id in
        SystemCommand(
            id: id, name: name(for: id), sfSymbol: symbol(for: id),
            confirmation: confirmation(for: id))
    }

    private static let byEntryID = Dictionary(uniqueKeysWithValues: all.map { ($0.entryID, $0) })

    static func command(forEntryID entryID: String) -> SystemCommand? {
        byEntryID[entryID]
    }

    private static func name(for id: SystemCommand.ID) -> String {
        switch id {
        case .lockScreen: return "Lock Screen"
        case .sleep: return "Sleep"
        case .sleepDisplays: return "Sleep Displays"
        case .restart: return "Restart"
        case .shutDown: return "Shut Down"
        case .logOut: return "Log Out"
        case .showScreenSaver: return "Show Screen Saver"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .toggleMute: return "Toggle Mute"
        case .volumeUp: return "Turn Volume Up"
        case .volumeDown: return "Turn Volume Down"
        case .setVolume: return "Set Volume…"
        case .volume0: return "Set Volume to 0%"
        case .volume25: return "Set Volume to 25%"
        case .volume50: return "Set Volume to 50%"
        case .volume75: return "Set Volume to 75%"
        case .volume100: return "Set Volume to 100%"
        case .showDesktop: return "Show Desktop"
        case .toggleAppearance: return "Toggle System Appearance"
        case .toggleStageManager: return "Toggle Stage Manager"
        case .openTrash: return "Open Trash"
        case .emptyTrash: return "Empty Trash"
        case .ejectAllDisks: return "Eject All Disks"
        case .toggleHiddenFiles: return "Toggle Hidden Files"
        case .hideOtherApps: return "Hide All Apps Except Frontmost"
        case .unhideAllApps: return "Unhide All Hidden Apps"
        case .quitAllApps: return "Quit All Applications"
        case .dismissNotifications: return "Dismiss Notifications"
        case .toggleBluetooth: return "Toggle Bluetooth"
        }
    }

    private static func symbol(for id: SystemCommand.ID) -> String {
        switch id {
        case .lockScreen: return "lock"
        case .sleep: return "moon.zzz"
        case .sleepDisplays: return "display"
        case .restart: return "arrow.clockwise"
        case .shutDown: return "power"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        case .showScreenSaver: return "rectangle.inset.filled"
        case .playPause: return "playpause"
        case .nextTrack: return "forward.end"
        case .previousTrack: return "backward.end"
        case .toggleMute: return "speaker.slash"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .setVolume, .volume0, .volume25, .volume50, .volume75, .volume100:
            return "speaker.wave.2"
        case .showDesktop: return "macwindow.on.rectangle"
        case .toggleAppearance: return "circle.lefthalf.filled"
        case .toggleStageManager: return "squares.leading.rectangle"
        case .openTrash: return "trash"
        case .emptyTrash: return "trash.slash"
        case .ejectAllDisks: return "eject"
        case .toggleHiddenFiles: return "eye.slash"
        case .hideOtherApps: return "eye.slash.circle"
        case .unhideAllApps: return "eye.circle"
        case .quitAllApps: return "xmark.circle"
        case .dismissNotifications: return "bell.slash"
        // Not an SF Symbol — the logo is a Bluetooth SIG trademark, so this resolves to a bundled asset instead.
        case .toggleBluetooth: return "bluetooth"
        }
    }

    private static func confirmation(for id: SystemCommand.ID) -> SystemCommand.Confirmation {
        switch id {
        case .restart, .shutDown, .logOut, .emptyTrash, .quitAllApps:
            return .required
        default:
            return .none
        }
    }
}
