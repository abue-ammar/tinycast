import Foundation

/// What the iCloud Sync pane lists; each optional one is a per-Mac choice, on unless `isOptIn`.
enum SyncCategory: String, CaseIterable, Codable, Sendable {
    case aiCommands, aiChats, dictation, mcpServers, quicklinks, notes, snippets
    case clipboardText, clipboardImages, windowLayouts, extensions
    case launchAtLogin, showInMenuBar, appearance, interfaceSize, windowMode
    case hotkeysAndAliases, favoritesAndFallbacks, otherSettings

    enum Group: CaseIterable, Sendable {
        case content, general, always
    }

    var group: Group {
        switch self {
        case .aiCommands, .aiChats, .dictation, .mcpServers, .quicklinks, .notes, .snippets,
            .clipboardText, .clipboardImages, .windowLayouts, .extensions:
            .content
        case .launchAtLogin, .showInMenuBar, .appearance, .interfaceSize, .windowMode: .general
        case .hotkeysAndAliases, .favoritesAndFallbacks, .otherSettings: .always
        }
    }

    var isOptional: Bool { group != .always }

    /// What you copy can be private, so the clipboard syncs only once a Mac turns it on.
    var isOptIn: Bool { self == .clipboardText || self == .clipboardImages }

    /// Whether the pane counts its items; a setting is one value, not a collection.
    var isCounted: Bool {
        switch self {
        case .aiCommands, .aiChats, .mcpServers, .quicklinks, .notes, .snippets, .clipboardText,
            .clipboardImages, .extensions:
            true
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
        case .clipboardText: String(localized: "Clipboard Text")
        case .clipboardImages: String(localized: "Clipboard Images")
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

    /// A whole feature's row is that feature's tab icon; a part of one takes only its tint.
    var symbol: String {
        switch self {
        case .aiCommands: "sparkles"
        case .aiChats: "bubble.left.fill"
        case .dictation: "waveform"
        case .mcpServers: "server.rack"
        case .quicklinks: "link"
        case .notes: "text.page.fill"
        case .snippets: "curlybraces"
        case .clipboardText: "text.alignleft"
        case .clipboardImages: "photo.fill"
        case .windowLayouts: "rectangle.split.2x2.fill"
        case .extensions: "puzzlepiece.extension.fill"
        case .launchAtLogin: "power"
        case .showInMenuBar: "menubar.rectangle"
        case .appearance: "paintbrush.fill"
        case .interfaceSize: "textformat.size"
        case .windowMode: "macwindow"
        case .hotkeysAndAliases: "keyboard.fill"
        case .favoritesAndFallbacks: "star.fill"
        case .otherSettings: "gearshape.fill"
        }
    }

    var tint: IconTint {
        switch self {
        case .aiCommands, .aiChats, .mcpServers: .purple
        case .dictation: .pink
        case .quicklinks: .blue
        case .notes: .yellow
        case .snippets: .brown
        case .clipboardText, .clipboardImages: .indigo
        case .windowLayouts: .mint
        case .extensions: .green
        case .hotkeysAndAliases: .graphite
        case .launchAtLogin, .showInMenuBar, .appearance, .interfaceSize, .windowMode,
            .favoritesAndFallbacks, .otherSettings:
            .gray
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
        case .clipboardImages:
            String(localized: "Images count toward your iCloud storage.")
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
