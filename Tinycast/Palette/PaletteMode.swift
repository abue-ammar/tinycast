import AppKit

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case calculatorHistory
    case emoji
    case fileSearch
    case uninstall
    case quicklinks
    /// Collects a quicklink's `{argument}` values; the request lives on the session.
    case quicklinkArguments

    var id: String { rawValue }
    var title: String {
        switch self {
        case .launcher: return "Apps"
        case .clipboard: return "Clipboard"
        case .calculatorHistory: return "Calculator History"
        case .emoji: return "Emoji & Symbols"
        case .fileSearch: return "Search Files"
        case .uninstall: return "Uninstall Application"
        case .quicklinks: return "Quicklinks"
        case .quicklinkArguments: return "Open Quicklink"
        }
    }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .uninstall: return "trash"
        case .quicklinks, .quicklinkArguments: return Quicklink.sfSymbol
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .emoji: return "Search emoji and symbols…"
        case .fileSearch: return "Search files and folders…"
        case .uninstall: return "Filter files and folders by name…"
        case .quicklinks: return "Search quicklinks…"
        // Replaced by the pending argument's name; only reached if the session vanished mid-render.
        case .quicklinkArguments: return "Enter a value…"
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
