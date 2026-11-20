import Foundation

struct SystemAction: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Codable, Sendable {
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
        case toggleMicrophoneMute = "toggle-microphone-mute"
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

    /// Whether it confirms first, and the copy; every such action is destructive.
    enum Confirmation: Hashable, Sendable {
        case none
        case required(title: String, message: String)
        /// Asks only while Finder's own "Show warning before emptying the Trash" is on.
        case followsFinder(title: String, message: String)
        /// Quit All alone counts its targets before asking, so its copy is built at call time.
        case computed
    }

    let id: ID
    let name: String
    let englishName: String
    let sfSymbol: String
    let tint: IconTint
    let confirmation: Confirmation

    /// Stable identity for the entry, and with it every persisted key it owns.
    var entryID: String { "system-action:" + id.rawValue }
}

enum SystemActionCatalog {
    static let all: [SystemAction] = SystemAction.ID.allCases.map { id in
        let name = name(for: id)
        return SystemAction(
            id: id, name: name.resolved(), englishName: name.key, sfSymbol: symbol(for: id),
            tint: tint(for: id), confirmation: confirmation(for: id))
    }

    private static let byEntryID = Dictionary(uniqueKeysWithValues: all.map { ($0.entryID, $0) })
    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func action(forEntryID entryID: String) -> SystemAction? {
        byEntryID[entryID]
    }

    static func action(id: SystemAction.ID) -> SystemAction {
        // Every ID is in `all` by construction, so a miss is a programmer error.
        byID[id]!
    }

    private static func name(for id: SystemAction.ID) -> LocalizedStringResource {
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
        case .toggleMicrophoneMute: return "Toggle Microphone Mute"
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

    private static func symbol(for id: SystemAction.ID) -> String {
        switch id {
        case .lockScreen: return "lock.fill"
        case .sleep: return "moon.zzz.fill"
        case .sleepDisplays: return "display"
        case .restart: return "arrow.clockwise"
        case .shutDown: return "power"
        case .logOut: return "rectangle.portrait.and.arrow.right.fill"
        case .showScreenSaver: return "rectangle.inset.filled"
        case .playPause: return "playpause.fill"
        case .nextTrack: return "forward.end.fill"
        case .previousTrack: return "backward.end.fill"
        case .toggleMute: return "speaker.slash.fill"
        case .toggleMicrophoneMute: return "mic.slash.fill"
        case .volumeUp: return "speaker.plus.fill"
        case .volumeDown: return "speaker.minus.fill"
        case .volume0: return "speaker.fill"
        case .volume25: return "speaker.wave.1.fill"
        case .setVolume, .volume50: return "speaker.wave.2.fill"
        case .volume75, .volume100: return "speaker.wave.3.fill"
        case .showDesktop: return "macwindow.on.rectangle"
        case .toggleAppearance: return "circle.lefthalf.filled"
        case .toggleStageManager: return "squares.leading.rectangle.fill"
        case .openTrash: return "trash.fill"
        case .emptyTrash: return "trash.slash.fill"
        case .ejectAllDisks: return "eject.fill"
        case .toggleHiddenFiles: return "eye.slash.fill"
        case .hideOtherApps: return "eye.slash.circle.fill"
        case .unhideAllApps: return "eye.circle.fill"
        case .quitAllApps: return "xmark.circle.fill"
        case .dismissNotifications: return "bell.slash.fill"
        // Not an SF Symbol: the logo is a trademark, so this is a bundled asset.
        case .toggleBluetooth: return "bluetooth"
        }
    }

    private static func tint(for id: SystemAction.ID) -> IconTint {
        switch id {
        case .lockScreen, .toggleAppearance: return .graphite
        case .sleep, .sleepDisplays: return .indigo
        case .restart: return .orange
        case .showScreenSaver: return .cyan
        case .playPause, .nextTrack, .previousTrack: return .pink
        case .logOut, .openTrash, .ejectAllDisks: return .gray
        case .showDesktop, .toggleStageManager, .toggleHiddenFiles, .hideOtherApps, .unhideAllApps,
            .toggleBluetooth:
            return .blue
        case .shutDown, .toggleMute, .toggleMicrophoneMute, .volumeUp, .volumeDown, .setVolume, .volume0,
            .volume25, .volume50, .volume75, .volume100, .emptyTrash, .quitAllApps, .dismissNotifications:
            return .red
        }
    }

    private static let sessionEndingMessage =
        String(localized: "Applications with unsaved changes may ask you to save.")

    private static func confirmation(for id: SystemAction.ID) -> SystemAction.Confirmation {
        switch id {
        case .restart:
            return .required(
                title: String(localized: "Restart your Mac?"), message: sessionEndingMessage)
        case .shutDown:
            return .required(
                title: String(localized: "Shut down your Mac?"), message: sessionEndingMessage)
        case .logOut:
            return .required(title: String(localized: "Log out now?"), message: sessionEndingMessage)
        case .emptyTrash:
            return .followsFinder(
                title: String(localized: "Empty Trash?"),
                message: String(localized: "The items in the Trash will be permanently deleted."))
        case .quitAllApps:
            return .computed
        default:
            return .none
        }
    }
}
