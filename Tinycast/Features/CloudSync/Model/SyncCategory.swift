import Foundation

/// What the iCloud Sync pane lists; each optional one is a per-Mac choice, on by default.
enum SyncCategory: String, CaseIterable, Codable, Sendable {
    case aiCommands, aiChats, dictation, mcpServers, quicklinks, notes, snippets, windowLayouts
    case extensions
    case launchAtLogin, showInMenuBar, appearance, interfaceSize, windowMode
    case hotkeysAndAliases, favoritesAndFallbacks, otherSettings

    enum Group: CaseIterable, Sendable {
        case content, general, always
    }

    var group: Group {
        switch self {
        case .aiCommands, .aiChats, .dictation, .mcpServers, .quicklinks, .notes, .snippets,
            .windowLayouts, .extensions:
            .content
        case .launchAtLogin, .showInMenuBar, .appearance, .interfaceSize, .windowMode: .general
        case .hotkeysAndAliases, .favoritesAndFallbacks, .otherSettings: .always
        }
    }

    var isOptional: Bool { group != .always }

    /// Whether the pane counts its items; a setting is one value, not a collection.
    var isCounted: Bool {
        switch self {
        case .aiCommands, .aiChats, .mcpServers, .quicklinks, .notes, .snippets, .extensions: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .aiCommands: String(localized: "AI Commands & Presets")
        case .aiChats: String(localized: "AI Chat History")
        case .dictation: String(localized: "Dictation")
        case .mcpServers: String(localized: "MCP Servers")
        case .quicklinks: String(localized: "Quicklinks")
        case .notes: String(localized: "Notes")
        case .snippets: String(localized: "Snippets")
        case .windowLayouts: String(localized: "Window Layouts")
        case .extensions: String(localized: "Extensions")
        case .launchAtLogin: String(localized: "Open at Login")
        case .showInMenuBar: String(localized: "Show in Menu Bar")
        case .appearance: String(localized: "Appearance")
        case .interfaceSize: String(localized: "Interface Size")
        case .windowMode: String(localized: "Window Mode")
        case .hotkeysAndAliases: String(localized: "Hotkeys & Aliases")
        case .favoritesAndFallbacks: String(localized: "Favorites & Fallback Order")
        case .otherSettings: String(localized: "Other Settings")
        }
    }

    var symbol: String {
        switch self {
        case .aiCommands: "sparkles"
        case .aiChats: "bubble.left.and.bubble.right"
        case .dictation: "mic"
        case .mcpServers: "server.rack"
        case .quicklinks: "link"
        case .notes: "note.text"
        case .snippets: "text.badge.plus"
        case .windowLayouts: "rectangle.split.2x2"
        case .extensions: "puzzlepiece.extension"
        case .launchAtLogin: "power"
        case .showInMenuBar: "menubar.rectangle"
        case .appearance: "paintbrush"
        case .interfaceSize: "textformat.size"
        case .windowMode: "macwindow"
        case .hotkeysAndAliases: "keyboard"
        case .favoritesAndFallbacks: "star"
        case .otherSettings: "gearshape"
        }
    }

    /// The pane's info tip; nil where the title says it all.
    var detail: String? {
        switch self {
        case .aiChats:
            String(localized: "Attachments stay on the Mac they were added on.")
        case .mcpServers:
            String(localized: "Credentials stay on each Mac, and a new server asks before it runs.")
        case .extensions:
            String(
                localized: """
                    Store extensions install on every Mac where Extensions is on. Passwords and file \
                    paths in their preferences stay on each Mac.
                    """)
        case .dictation:
            String(localized: "The model and microphone stay on each Mac.")
        case .hotkeysAndAliases:
            String(
                localized: """
                    A shortcut whose app or item isn't on a Mac yet waits until it is, and one that \
                    clashes there keeps that Mac's choice.
                    """)
        case .otherSettings:
            String(localized: "Feature switches, folders and language stay on each Mac.")
        default: nil
        }
    }

    static func categories(in group: Group) -> [SyncCategory] {
        allCases.filter { $0.group == group }
    }
}
