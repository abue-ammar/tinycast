import Foundation

/// App-internal launcher actions surfaced as a "Commands" category; each is a synthetic `AppEntry` (kind `.command`, no bundle ID) so existing `AppEntry` plumbing applies, with dispatch in `AppCore.runCommand`.
enum CommandID: String, CaseIterable, Sendable {
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case searchEmoji = "command:search-emoji"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case settings = "command:settings"
    case about = "command:about"
    case quitAllApps = "command:quit-all-apps"
    case quit = "command:quit"

    var name: String {
        switch self {
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .exportSettings: return "Export Settings"
        case .importSettings: return "Import Settings"
        case .importFromRaycast: return "Import from Raycast"
        case .settings: return "Settings"
        case .about: return "About Tinycast"
        case .quitAllApps: return "Quit All Applications"
        case .quit: return "Quit Tinycast"
        }
    }

    var sfSymbol: String {
        switch self {
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .searchEmoji: return "face.smiling"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .quitAllApps: return "xmark.circle"
        case .quit: return "power"
        }
    }
}

enum CommandRegistry {
    /// Sorted by name to keep the AppIndex sort invariant; the URL is a placeholder since commands are never launched from disk.
    nonisolated static let all: [AppEntry] =
        CommandID.allCases
        .map { id in
            AppEntry(
                id: id.rawValue, name: id.name,
                url: URL(
                    string: "tinycast://" + id.rawValue.replacingOccurrences(of: ":", with: "/"))!,
                bundleID: nil, kind: .command)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static func command(for entry: AppEntry) -> CommandID? {
        CommandID(rawValue: entry.id)
    }
}
