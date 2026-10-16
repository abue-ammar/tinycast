import AppKit

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case ai
    case aiHistory
    case calculatorHistory
    case emoji
    case fileSearch
    case menuSearch
    case switchWindows
    case rooms
    /// Choosing a room's windows and apps; the room was named on the Rooms screen.
    case roomWindows
    case schedule
    case eventEditor
    case customCommandEditor
    case customCommands
    /// One meeting's read-only page, pushed from that meeting's own actions.
    case meetingDetails
    case uninstall
    case quicklinks
    case quicklinkEditor
    case snippets
    case snippetEditor
    case dictionary
    case extensionCommand

    var id: String { rawValue }

    var isNativeEditor: Bool {
        self == .snippetEditor || self == .quicklinkEditor || self == .eventEditor
            || self == .customCommandEditor
    }

    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .ai: return "sparkles"
        case .aiHistory: return "clock.arrow.circlepath"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .menuSearch: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .rooms: return "door.left.hand.open"
        case .roomWindows: return "macwindow.badge.plus"
        case .schedule: return "calendar"
        case .eventEditor: return "calendar.badge.plus"
        case .customCommandEditor, .customCommands: return CustomCommand.sfSymbol
        case .meetingDetails: return "calendar"
        case .uninstall: return "trash"
        case .quicklinks, .quicklinkEditor: return Quicklink.sfSymbol
        case .snippets, .snippetEditor: return "curlybraces"
        case .dictionary: return "book.closed"
        case .extensionCommand: return "puzzlepiece.extension"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return String(localized: "Search for apps and commands…")
        case .clipboard: return String(localized: "Type to filter entries…")
        case .ai: return String(localized: "Ask anything…")
        case .aiHistory: return String(localized: "Search chats…")
        case .calculatorHistory:
            return String(localized: "Do math, convert units, or search your past calculations…")
        case .emoji: return String(localized: "Search emoji and symbols…")
        case .fileSearch: return String(localized: "Search files and folders…")
        case .menuSearch: return String(localized: "Search menu bar items…")
        case .switchWindows: return String(localized: "Search open windows…")
        case .rooms: return String(localized: "Search rooms, or name a new one…")
        case .roomWindows: return String(localized: "Search windows, or type an app to add…")
        case .schedule: return String(localized: "Search your schedule…")
        case .eventEditor: return String(localized: "Event editor")
        case .customCommandEditor: return String(localized: "Command editor")
        case .customCommands: return String(localized: "Search custom commands…")
        case .meetingDetails: return String(localized: "Meeting details")
        case .uninstall: return String(localized: "Filter files and folders by name…")
        case .quicklinks: return String(localized: "Search quicklinks…")
        case .quicklinkEditor: return String(localized: "Quicklink editor")
        case .snippets: return String(localized: "Search snippets…")
        case .snippetEditor: return String(localized: "Snippet editor")
        case .dictionary: return String(localized: "Look up a word…")
        // Replaced by the command's own `searchBarPlaceholder` whenever it declares one.
        case .extensionCommand: return String(localized: "Search…")
        }
    }
}

/// The app a paste lands in, resolved once per show so nothing re-reads it per render.
struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { String(localized: "Paste to \(name)") }
}
