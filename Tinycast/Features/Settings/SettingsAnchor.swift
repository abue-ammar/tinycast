/// One `Section` inside a pane, named once so the catalog and the pane cannot disagree: the search
/// result carries the anchor, the pane's `.settingsAnchor(_:)` marks the section it scrolls to.
struct SettingsAnchor: Hashable, Sendable {
    let tab: SettingsTab
    /// The `Section`'s own header text, which is also what a result's breadcrumb reads.
    let title: String
}

// Named `<pane><Section>` throughout, so the constant for a section is always guessable from it.
extension SettingsAnchor {
    static let generalGlobalShortcuts = Self(tab: .general, title: "Global Shortcuts")
    static let generalSearch = Self(tab: .general, title: "Search")
    static let generalHyperKey = Self(tab: .general, title: "Hyper Key")
    static let generalAppearance = Self(tab: .general, title: "Appearance")
    static let generalGeneral = Self(tab: .general, title: "General")

    static let applicationsSearchScopes = Self(tab: .applications, title: "Search Scopes")
    static let applicationsApplications = Self(tab: .applications, title: "Applications")

    static let systemSettingsSystemSettings = Self(tab: .systemSettings, title: "System Settings")

    static let systemActionsSystemActions = Self(tab: .systemActions, title: "System Actions")

    static let commandsCommands = Self(tab: .commands, title: "Commands")
    static let commandsCustomCommands = Self(tab: .commands, title: "Custom Commands")

    static let quicklinksQuicklinks = Self(tab: .quicklinks, title: "Quicklinks")
    static let quicklinksBehaviour = Self(tab: .quicklinks, title: "Behaviour")
    static let quicklinksImportExport = Self(tab: .quicklinks, title: "Import & Export")

    static let fallbacksFallbacks = Self(tab: .fallbacks, title: "Fallbacks")

    static let aiAI = Self(tab: .ai, title: "AI")
    static let aiDefault = Self(tab: .ai, title: "Default")
    static let aiChat = Self(tab: .ai, title: "Chat")
    static let aiConversations = Self(tab: .ai, title: "Conversations")
    static let aiSystemPrompt = Self(tab: .ai, title: "System prompt")
    static let aiChatGPTSubscription = Self(tab: .ai, title: "ChatGPT Subscription")
    static let aiAPIConnections = Self(tab: .ai, title: "API Connections")
    static let aiMCPServers = Self(tab: .ai, title: "MCP Servers")
    static let aiCommands = Self(tab: .ai, title: "Commands")

    static let quickActionsQuickActions = Self(tab: .quickActions, title: "Quick Actions")
    static let quickActionsActions = Self(tab: .quickActions, title: "Actions")
    static let quickActionsModel = Self(tab: .quickActions, title: "Model")
    static let quickActionsTranslate = Self(tab: .quickActions, title: "Translate")

    static let fileSearchFileSearch = Self(tab: .fileSearch, title: "File Search")
    static let fileSearchCommands = Self(tab: .fileSearch, title: "Commands")
    static let fileSearchSearchScopes = Self(tab: .fileSearch, title: "Search Scopes")
    static let fileSearchIgnorePatterns = Self(tab: .fileSearch, title: "Ignore Patterns")

    static let notesNotes = Self(tab: .notes, title: "Notes")
    static let notesCommands = Self(tab: .notes, title: "Commands")

    static let snippetsSnippets = Self(tab: .snippets, title: "Snippets")
    static let snippetsGlobalShortcut = Self(tab: .snippets, title: "Global Shortcut")
    static let snippetsLibrary = Self(tab: .snippets, title: "Library")

    static let windowManagementWindowManagement = Self(
        tab: .windowManagement, title: "Window Management")
    static let windowManagementOptions = Self(tab: .windowManagement, title: "Options")

    static let clipboardGlobalShortcuts = Self(tab: .clipboard, title: "Global Shortcuts")
    static let clipboardHistory = Self(tab: .clipboard, title: "History")
    static let clipboardDisabledApplications = Self(
        tab: .clipboard, title: "Disabled Applications")

    static let emojiGlobalShortcuts = Self(tab: .emoji, title: "Global Shortcuts")
    static let emojiAppearance = Self(tab: .emoji, title: "Appearance")

    static let calendarCalendar = Self(tab: .calendar, title: "Calendar")
    static let calendarSchedule = Self(tab: .calendar, title: "Schedule")
    static let calendarJoining = Self(tab: .calendar, title: "Joining")
    static let calendarMenuBar = Self(tab: .calendar, title: "Menu Bar")
    static let calendarCalendars = Self(tab: .calendar, title: "Calendars")

    static let extensionsExtensions = Self(tab: .extensions, title: "Extensions")
    static let extensionsCompatibility = Self(tab: .extensions, title: "Compatibility")
    static let extensionsInstalled = Self(tab: .extensions, title: "Installed")
    static let extensionsInstall = Self(tab: .extensions, title: "Install")
    static let extensionsStorage = Self(tab: .extensions, title: "Storage")

    static let permissionsAccessibility = Self(tab: .permissions, title: "Accessibility")
    static let permissionsCalendars = Self(tab: .permissions, title: "Calendars")

    static let backupExport = Self(tab: .backup, title: "Export")
    static let backupImport = Self(tab: .backup, title: "Import")
    static let backupImportFromRaycast = Self(tab: .backup, title: "Import from Raycast")

    static let aboutAbout = Self(tab: .about, title: "About")
    static let aboutLinks = Self(tab: .about, title: "Links")
}

/// Where a search result lands: a whole section, or one row inside it.
enum SettingsTarget: Hashable, Sendable {
    case section(SettingsAnchor)
    /// The row's visible title, which is also the catalog entry's — they are the same string.
    case row(SettingsAnchor, String)

    var anchor: SettingsAnchor {
        switch self {
        case .section(let anchor), .row(let anchor, _): return anchor
        }
    }

    var tab: SettingsTab { anchor.tab }
}

/// One jump asked for by a search result. The token is what makes picking the same result twice
/// scroll and pulse again, rather than comparing equal and doing nothing.
struct SettingsScrollRequest: Equatable, Sendable {
    let target: SettingsTarget
    let token: Int
}
