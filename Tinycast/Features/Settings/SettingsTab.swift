enum SettingsTab: CaseIterable, Identifiable {
    case general, applications, systemSettings, systemActions, commands, quicklinks, fileSearch,
        snippets, windowManagement, clipboard, emoji, extensions, permissions, backup, about
    /// The case, never an index: a selectable `List` flattens section and row IDs together.
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .applications: return "Applications"
        case .systemSettings: return "System Settings"
        case .systemActions: return "System Actions"
        case .commands: return "Commands"
        case .quicklinks: return "Quicklinks"
        case .fileSearch: return "File Search"
        case .snippets: return "Snippets"
        case .windowManagement: return "Window Management"
        case .clipboard: return "Clipboard"
        case .emoji: return "Emoji & Symbols"
        case .extensions: return "Extensions"
        case .permissions: return "Permissions"
        case .backup: return "Backup"
        case .about: return "About"
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
        case .fileSearch: return "doc.text.magnifyingglass"
        case .snippets: return "curlybraces"
        case .windowManagement: return "macwindow"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
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
        case .general: return "General"
        case .launcher: return "Launcher"
        case .features: return "Features"
        case .advanced: return "Advanced"
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .general: return [.general, .permissions]
        case .launcher:
            return [.applications, .systemSettings, .systemActions, .commands, .quicklinks]
        case .features:
            return [.fileSearch, .snippets, .windowManagement, .clipboard, .emoji, .extensions]
        case .advanced: return [.backup, .about]
        }
    }
}
