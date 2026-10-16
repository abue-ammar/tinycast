enum SettingsTab: CaseIterable, Identifiable {
    case general, applications, systemSettings, systemActions, commands, quicklinks, appleShortcuts,
        fallbacks, clipboard, snippets, fileSearch, windowManagement, navigation, notes, calendar, emoji,
        dictation, ai, quickActions, extensions, permissions, backup, about
    /// The case, never an index: a selectable `List` flattens section and row IDs together.
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .applications: return String(localized: "Applications")
        case .systemSettings: return String(localized: "System Settings")
        case .systemActions: return String(localized: "System Actions")
        case .commands: return String(localized: "Commands")
        case .quicklinks: return String(localized: "Quicklinks")
        case .appleShortcuts: return String(localized: "Apple Shortcuts")
        case .fallbacks: return String(localized: "Fallbacks")
        case .ai: return String(localized: "AI")
        case .quickActions: return String(localized: "Quick Actions")
        case .dictation: return String(localized: "Dictation")
        case .fileSearch: return String(localized: "File Search")
        case .notes: return String(localized: "Notes")
        case .snippets: return String(localized: "Snippets")
        case .navigation: return String(localized: "Navigation")
        case .windowManagement: return String(localized: "Window Management")
        case .clipboard: return String(localized: "Clipboard")
        case .emoji: return String(localized: "Emoji & Symbols")
        case .calendar: return String(localized: "Calendar")
        case .extensions: return String(localized: "Extensions")
        case .permissions: return String(localized: "Permissions")
        case .backup: return String(localized: "Backup")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .applications: return "square.grid.2x2"
        case .systemSettings: return "gearshape"
        case .systemActions: return "bolt"
        case .commands: return "terminal"
        case .quicklinks: return "link"
        case .appleShortcuts: return "square.2.layers.3d"
        case .fallbacks: return "arrow.turn.down.right"
        case .ai: return "sparkles"
        case .quickActions: return "wand.and.sparkles"
        case .dictation: return "waveform"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .notes: return "text.page"
        case .snippets: return "curlybraces"
        case .navigation: return "arrow.left.arrow.right"
        case .windowManagement: return "macwindow"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
        case .calendar: return "calendar"
        case .extensions: return "puzzlepiece.extension"
        case .permissions: return "lock.shield"
        case .backup: return "arrow.up.arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

/// Declaration order is display order; not `.Section`, which would shadow SwiftUI's `Section`.
enum SettingsSection: CaseIterable, Identifiable {
    case general, launcher, features, advanced
    /// See `SettingsTab.id`: distinct types keep the two namespaces from colliding.
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .launcher: return String(localized: "Launcher")
        case .features: return String(localized: "Features")
        case .advanced: return String(localized: "Advanced")
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .general: return [.general, .permissions]
        case .launcher:
            return [
                .applications, .systemSettings, .systemActions, .commands, .quicklinks,
                .appleShortcuts, .fallbacks
            ]
        case .features:
            // Everyday tools first; AI and extensions are opt-in extras.
            return [
                .clipboard, .snippets, .fileSearch, .windowManagement, .navigation, .notes,
                .calendar, .emoji, .dictation, .ai, .quickActions, .extensions
            ]
        case .advanced: return [.backup, .about]
        }
    }
}
