import Foundation

/// Built-in launcher actions, surfaced alongside the user-authored ones.
enum CommandID: String, CaseIterable, Sendable {
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case searchEmoji = "command:search-emoji"
    case searchFiles = "command:search-files"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createQuicklink = "command:create-quicklink"
    case searchQuicklinks = "command:search-quicklinks"
    case importQuicklinks = "command:import-quicklinks"
    case exportQuicklinks = "command:export-quicklinks"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case settings = "command:settings"
    case about = "command:about"
    case quit = "command:quit"

    var name: String {
        switch self {
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .searchFiles: return "Search Files"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createQuicklink: return "Create Quicklink"
        case .searchQuicklinks: return "Search Quicklinks"
        case .importQuicklinks: return "Import Quicklinks"
        case .exportQuicklinks: return "Export Quicklinks"
        case .exportSettings: return "Export Settings"
        case .importSettings: return "Import Settings"
        case .importFromRaycast: return "Import from Raycast"
        case .settings: return "Settings"
        case .about: return "About Tinycast"
        case .quit: return "Quit Tinycast"
        }
    }

    var sfSymbol: String {
        switch self {
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .searchEmoji: return "face.smiling"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .showNotes: return "text.page"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createQuicklink: return "link.badge.plus"
        case .searchQuicklinks: return Quicklink.sfSymbol
        case .importQuicklinks: return "square.and.arrow.down"
        case .exportQuicklinks: return "square.and.arrow.up"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .quit: return "power"
        }
    }

    /// The built-ins with a global shortcut of their own; the rest open from the launcher.
    var hotKeyAction: HotKeyAction? {
        switch self {
        case .searchFiles: return .searchFiles
        case .clipboardHistory: return .toggleClipboard
        case .searchEmoji: return .toggleEmoji
        case .showNotes: return .showNotes
        case .createNote: return .createNote
        case .searchNotes: return .searchNotes
        default: return nil
        }
    }
}
