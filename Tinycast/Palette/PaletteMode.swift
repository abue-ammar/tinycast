import AppKit

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case ai
    case aiHistory
    case calculatorHistory
    case emoji
    case fileSearch
    case schedule
    case uninstall
    case quicklinks
    case snippets
    /// Collects a custom command's positional arguments, held on its own session.
    case customCommandArguments
    /// A Raycast extension command rendering into the palette.
    case extensionCommand

    var id: String { rawValue }

    /// One value at a time into the search field, so ↵ still acts with no rows to select.
    var isArgumentForm: Bool { self == .customCommandArguments }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .ai: return "sparkles"
        case .aiHistory: return "clock.arrow.circlepath"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .schedule: return "calendar"
        case .uninstall: return "trash"
        case .quicklinks: return Quicklink.sfSymbol
        case .customCommandArguments: return CustomCommand.sfSymbol
        case .snippets: return "curlybraces"
        case .extensionCommand: return "puzzlepiece.extension"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return String(localized: "Search for apps and commands…", bundle: .appLanguage)
        case .clipboard: return String(localized: "Type to filter entries…", bundle: .appLanguage)
        case .ai: return String(localized: "Ask anything…", bundle: .appLanguage)
        case .aiHistory: return String(localized: "Search chats…", bundle: .appLanguage)
        case .calculatorHistory: return String(
            localized: "Do math, convert units, or search your past calculations…",
            bundle: .appLanguage)
        case .emoji: return String(localized: "Search emoji and symbols…", bundle: .appLanguage)
        case .fileSearch: return String(localized: "Search files and folders…", bundle: .appLanguage)
        case .schedule: return String(localized: "Search your schedule…", bundle: .appLanguage)
        case .uninstall: return String(localized: "Filter files and folders by name…", bundle: .appLanguage)
        case .quicklinks: return String(localized: "Search quicklinks…", bundle: .appLanguage)
        case .snippets: return String(localized: "Search snippets…", bundle: .appLanguage)
        // Replaced by the pending argument's name; only reached if the session vanished mid-render.
        case .customCommandArguments: return String(localized: "Enter a value…", bundle: .appLanguage)
        // Replaced by the command's own `searchBarPlaceholder` whenever it declares one.
        case .extensionCommand: return String(localized: "Search…", bundle: .appLanguage)
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

    var pasteTitle: String { String(localized: "Paste to \(name)", bundle: .appLanguage) }
}
