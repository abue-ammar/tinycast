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
    case uninstall
    case quicklinks
    case snippets
    case dictionary
    /// A Raycast extension command rendering into the palette.
    case extensionCommand

    var id: String { rawValue }

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
        case .uninstall: return "trash"
        case .quicklinks: return Quicklink.sfSymbol
        case .snippets: return "curlybraces"
        case .dictionary: return "book.closed"
        case .extensionCommand: return "puzzlepiece.extension"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .ai: return "Ask anything…"
        case .aiHistory: return "Search chats…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .emoji: return "Search emoji and symbols…"
        case .fileSearch: return "Search files and folders…"
        case .menuSearch: return "Search menu bar items…"
        case .switchWindows: return "Search open windows…"
        case .rooms: return "Search rooms, or name a new one…"
        case .roomWindows: return "Search windows, or type an app to add…"
        case .schedule: return "Search your schedule…"
        case .uninstall: return "Filter files and folders by name…"
        case .quicklinks: return "Search quicklinks…"
        case .snippets: return "Search snippets…"
        case .dictionary: return "Look up a word…"
        // Replaced by the command's own `searchBarPlaceholder` whenever it declares one.
        case .extensionCommand: return "Search…"
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

    var pasteTitle: String { "Paste to \(name)" }
}
