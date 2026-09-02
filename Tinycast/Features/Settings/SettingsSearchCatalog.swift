import Foundation

/// One searchable place in Settings: a pane, or a row inside one of its `Form` sections.
struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    let tab: SettingsTab
    /// Where picking this result lands; nil for the pane itself, which is its own result.
    let target: SettingsTarget?
    let title: String
    /// Words a user might type that the visible title doesn't contain.
    let keywords: [String]

    /// Taking the pane from the target is what makes a row filed under the wrong pane unwritable.
    private init(_ target: SettingsTarget, _ title: String, _ keywords: [String]) {
        self.tab = target.tab
        self.target = target
        self.title = title
        self.keywords = keywords
    }

    /// One setting, which its pane marks with a matching `SettingsRowTitle`.
    init(_ anchor: SettingsAnchor, _ title: String, keywords: [String] = []) {
        self.init(.row(anchor, title), title, keywords)
    }

    /// A whole group, for a result no single row answers — a list, or a section's master switch.
    init(group anchor: SettingsAnchor, _ title: String, keywords: [String] = []) {
        self.init(.section(anchor), title, keywords)
    }

    init(pane: SettingsTab, keywords: [String] = []) {
        self.tab = pane
        self.target = nil
        self.title = pane.title
        self.keywords = keywords
    }

    var anchor: SettingsAnchor? { target?.anchor }

    var id: String { "\(tab.title)/\(anchor?.title ?? "")/\(title)" }

    /// The result row's second line — "General", or "General › Hyper Key".
    var breadcrumb: String {
        guard let anchor, anchor.title != tab.title else { return tab.title }
        return "\(tab.title) › \(anchor.title)"
    }
}

/// What Settings offers to search. Hand-written: a `Form` can't be asked what rows it holds, so a
/// new row is searchable only once it is listed here.
enum SettingsSearchCatalog {
    struct Query: Sendable {
        let terms: [FuzzyMatch.Query]

        init(_ raw: String) {
            terms = raw.split(whereSeparator: \Character.isWhitespace).map {
                FuzzyMatch.Query(String($0))
            }
        }

        var isEmpty: Bool { terms.isEmpty }
    }

    static func results(for raw: String, limit: Int = 50) -> [SettingsSearchEntry] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        // Catalog order is the tie-break, so results don't reshuffle between equal-scoring rows.
        return
            entries
            .enumerated()
            .compactMap { item -> (entry: SettingsSearchEntry, score: Int, rank: Int)? in
                guard let score = score(query, item.element) else { return nil }
                return (item.element, score, item.offset)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }
            .prefix(limit)
            .map(\.entry)
    }

    /// Every term must land somewhere; a term matched in the title outranks one found off it.
    private static func score(_ query: Query, _ entry: SettingsSearchEntry) -> Int? {
        var titleScore = 0
        var titleMatches = 0
        for term in query.terms {
            if let match = FuzzyMatch.match(term, candidate: entry.title) {
                titleMatches += 1
                titleScore += match.score
                continue
            }
            guard
                entry.keywords.contains(where: { FuzzyMatch.match(term, candidate: $0) != nil })
                    || FuzzyMatch.match(term, candidate: entry.breadcrumb) != nil
            else { return nil }
        }

        let band: Int
        if titleMatches == query.terms.count {
            band = 2_000_000
        } else if titleMatches > 0 {
            band = 1_000_000
        } else {
            band = 0
        }
        // A pane outranks its own rows, so a bare "clipboard" lands on the pane rather than a row.
        return band + titleScore + (entry.anchor == nil ? 500_000 : 0)
    }

    // MARK: - The index
    // Pane order, then section order within a pane, so this reads as a table of contents.

    static let entries: [SettingsSearchEntry] =
        general + applications + systemSettings
        + systemActions + commands + quicklinks + fallbacks + ai + quickActions + fileSearch + notes
        + snippets + windowManagement + clipboard + emoji + calendar + extensions + permissions
        + backup + about

    private static let general: [SettingsSearchEntry] = [
        .init(pane: .general, keywords: ["preferences", "settings"]),
        .init(
            .generalGlobalShortcuts, "App Launcher",
            keywords: ["hotkey", "shortcut", "summon", "palette"]),
        .init(
            .generalSearch, "Learned ranking",
            keywords: ["reset", "history", "order", "privacy"]),
        .init(
            .generalHyperKey, "Hyper Key",
            keywords: ["modifier", "remap", "caps lock", "capslock"]),
        .init(
            .generalHyperKey, "Quick Press",
            keywords: ["tap", "escape", "single press"]),
        .init(
            .generalHyperKey, "Include Shift (⇧)",
            keywords: ["modifier", "chord"]),
        .init(
            .generalAppearance, "Theme",
            keywords: ["dark", "light", "mode", "appearance"]),
        .init(
            .generalAppearance, "Compact mode",
            keywords: ["slim", "search bar", "small"]),
        .init(
            .generalAppearance, "Show favorites in compact mode",
            keywords: ["pinned", "apps", "compact"]),
        .init(
            .generalAppearance, "Follow the cursor across displays",
            keywords: ["monitor", "screen", "pointer", "multi display"]),
        .init(
            .generalAppearance, "Drag to reposition",
            keywords: ["move", "position", "window"]),
        .init(
            .generalGeneral, "Launch at login",
            keywords: ["startup", "login item", "start", "boot"]),
        .init(
            .generalGeneral, "Show in menu bar",
            keywords: ["menubar", "status item", "icon", "hide"]),
        .init(
            .generalGeneral, "Pop to Root Search",
            keywords: ["reset", "timeout", "back"]),
        .init(
            .generalGeneral, "Auto-switch input source",
            keywords: ["keyboard", "layout", "language", "abc"])
    ]

    private static let applications: [SettingsSearchEntry] = [
        .init(pane: .applications, keywords: ["apps", "index", "launcher"]),
        .init(
            group: .applicationsSearchScopes, "Search Scopes",
            keywords: ["folders", "indexed", "locations", "add folder"]),
        .init(
            .applicationsApplications, "Enable Applications",
            keywords: ["hide apps", "visibility"]),
        .init(
            group: .applicationsApplications, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "per app", "hide"])
    ]

    private static let systemSettings: [SettingsSearchEntry] = [
        .init(
            pane: .systemSettings,
            keywords: ["panes", "preferences", "macos"]),
        .init(
            .systemSettingsSystemSettings, "Enable System Settings",
            keywords: ["hide panes", "visibility"])
    ]

    private static let systemActions: [SettingsSearchEntry] = [
        .init(
            pane: .systemActions,
            keywords: ["sleep", "lock", "restart", "shut down", "empty trash"]),
        .init(
            .systemActionsSystemActions, "Enable System Actions",
            keywords: ["hide", "visibility"])
    ]

    private static let commands: [SettingsSearchEntry] = [
        .init(
            pane: .commands,
            keywords: ["custom", "script", "shell", "terminal"]),
        .init(
            .commandsCommands, "Enable Commands",
            keywords: ["hide", "visibility"]),
        .init(
            .commandsCustomCommands, "Enable custom commands",
            keywords: ["script", "shell"]),
        .init(
            .commandsCustomCommands, "Add Custom Command",
            keywords: ["new", "script", "shell", "shortcut"])
    ]

    private static let quicklinks: [SettingsSearchEntry] = [
        .init(pane: .quicklinks, keywords: ["url", "bookmark", "link"]),
        .init(
            .quicklinksQuicklinks, "Enable quicklinks",
            keywords: ["url", "bookmark"]),
        .init(
            .quicklinksQuicklinks, "Add Quicklink",
            keywords: ["new", "url", "bookmark", "alias"]),
        .init(
            .quicklinksBehaviour, "Open in a new window",
            keywords: ["browser", "tab"]),
        .init(
            .quicklinksBehaviour, "When there's no selected text",
            keywords: ["selection", "fallback", "placeholder"]),
        .init(
            .quicklinksBehaviour, "Confirm before deleting",
            keywords: ["ask", "delete", "prompt"]),
        .init(
            .quicklinksImportExport, "Import quicklinks",
            keywords: ["json", "restore"]),
        .init(
            .quicklinksImportExport, "Export quicklinks",
            keywords: ["json", "backup"])
    ]

    private static let fallbacks: [SettingsSearchEntry] = [
        .init(
            pane: .fallbacks,
            keywords: ["no results", "empty", "search web", "order"])
    ]

    private static let ai: [SettingsSearchEntry] = [
        .init(pane: .ai, keywords: ["chat", "llm", "model", "openai", "anthropic"]),
        .init(.aiAI, "Enable AI", keywords: ["chat", "llm"]),
        .init(
            .aiDefault, "Default model",
            keywords: ["llm", "gpt", "claude"]),
        .init(
            .aiDefault, "Reasoning effort",
            keywords: ["thinking", "chatgpt"]),
        .init(.aiChat, "Web search", keywords: ["browse", "internet"]),
        .init(
            .aiConversations, "Opens to",
            keywords: ["new chat", "last", "summon"]),
        .init(
            .aiConversations, "Start a new conversation after",
            keywords: ["idle", "timeout", "fresh"]),
        .init(
            .aiConversations, "Keep conversations",
            keywords: ["retention", "delete", "history", "privacy"]),
        .init(
            .aiSystemPrompt, "Send a system prompt",
            keywords: ["instructions", "persona"]),
        .init(
            group: .aiChatGPTSubscription, "ChatGPT Subscription",
            keywords: ["sign in", "connect", "plus", "codex", "openai"]),
        .init(
            .aiAPIConnections, "Add API Connection",
            keywords: ["key", "provider", "openai", "anthropic", "ollama", "base url"]),
        .init(
            .aiMCPServers, "Enable MCP servers",
            keywords: ["tools", "model context protocol"]),
        .init(
            .aiMCPServers, "Add MCP Server",
            keywords: ["tools", "model context protocol", "stdio"]),
        .init(
            group: .aiCommands, "AI commands",
            keywords: ["shortcut", "launcher", "chat"])
    ]

    private static let quickActions: [SettingsSearchEntry] = [
        .init(
            pane: .quickActions,
            keywords: ["selected text", "rewrite", "translate", "summarize"]),
        .init(
            .quickActionsQuickActions, "Enable Quick Actions",
            keywords: ["selected text", "accessibility"]),
        .init(
            group: .quickActionsActions, "Actions",
            keywords: ["shortcut", "replace", "preview", "customize"]),
        .init(
            .quickActionsModel, "Model",
            keywords: ["llm", "ai", "default"]),
        .init(
            .quickActionsTranslate, "Translate to",
            keywords: ["language", "locale"])
    ]

    private static let fileSearch: [SettingsSearchEntry] = [
        .init(
            pane: .fileSearch,
            keywords: ["spotlight", "files", "folders", "find"]),
        .init(
            .fileSearchFileSearch, "Enable File Search",
            keywords: ["spotlight", "index"]),
        .init(
            group: .fileSearchCommands, "File search commands",
            keywords: ["shortcut", "launcher"]),
        .init(
            group: .fileSearchSearchScopes, "Search Scopes",
            keywords: ["folders", "locations", "home", "add folder"]),
        .init(
            group: .fileSearchIgnorePatterns, "Ignore Patterns",
            keywords: ["exclude", "glob", "node_modules", "skip"])
    ]

    private static let notes: [SettingsSearchEntry] = [
        .init(pane: .notes, keywords: ["markdown", "scratchpad", "floating"]),
        .init(
            .notesNotes, "Enable Notes",
            keywords: ["markdown", "scratchpad"]),
        .init(
            group: .notesCommands, "Notes commands",
            keywords: ["shortcut", "new note", "search notes"])
    ]

    private static let snippets: [SettingsSearchEntry] = [
        .init(
            pane: .snippets,
            keywords: ["expansion", "keyword", "text replacement", "template"]),
        .init(
            .snippetsSnippets, "Enable snippets",
            keywords: ["expansion", "keystrokes", "accessibility"]),
        .init(
            .snippetsGlobalShortcut, "Search Snippets",
            keywords: ["hotkey", "browser"]),
        .init(
            .snippetsLibrary, "New Snippet",
            keywords: ["add", "keyword", "expansion"]),
        .init(
            .snippetsLibrary, "Snippets Folder",
            keywords: ["reveal", "finder", "markdown", "files"])
    ]

    private static let windowManagement: [SettingsSearchEntry] = [
        .init(
            pane: .windowManagement,
            keywords: ["tile", "halves", "thirds", "maximize", "snap"]),
        .init(
            .windowManagementWindowManagement, "Enable window management",
            keywords: ["tile", "accessibility"]),
        .init(
            .windowManagementOptions, "Cycle sizes on repeat",
            keywords: ["repeat", "thirds", "halves"]),
        .init(
            .windowManagementOptions, "Gap between windows",
            keywords: ["padding", "spacing", "margin", "points"]),
        .init(
            group: .windowManagementOptions, "Window commands",
            keywords: ["shortcut", "left half", "maximize", "center"])
    ]

    private static let clipboard: [SettingsSearchEntry] = [
        .init(
            pane: .clipboard,
            keywords: ["paste", "history", "copy", "pasteboard"]),
        .init(
            .clipboardGlobalShortcuts, "Clipboard History",
            keywords: ["hotkey", "paste", "browser"]),
        .init(
            .clipboardHistory, "Keep history for",
            keywords: ["retention", "delete", "privacy", "expire"]),
        .init(
            group: .clipboardDisabledApplications, "Disabled Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy"]),
        .init(
            .clipboardDisabledApplications, "Clear history",
            keywords: ["delete", "erase", "wipe"])
    ]

    private static let emoji: [SettingsSearchEntry] = [
        .init(
            pane: .emoji,
            keywords: ["picker", "character", "unicode", "smiley"]),
        .init(
            .emojiGlobalShortcuts, "Emoji & Symbols",
            keywords: ["hotkey", "picker"]),
        .init(
            .emojiAppearance, "Emoji Skin Tone",
            keywords: ["colour", "color", "fitzpatrick", "default"])
    ]

    private static let calendar: [SettingsSearchEntry] = [
        .init(
            pane: .calendar,
            keywords: ["meetings", "events", "zoom", "join", "schedule"]),
        .init(
            .calendarCalendar, "Join meetings from Tinycast",
            keywords: ["zoom", "meet", "teams", "permission"]),
        .init(
            .calendarSchedule, "Upcoming meetings in launcher",
            keywords: ["count", "limit", "events"]),
        .init(
            .calendarSchedule, "Include Tomorrow's Events",
            keywords: ["next day", "range"]),
        .init(
            .calendarJoining, "Show the join card",
            keywords: ["hud", "timing", "early", "reminder"]),
        .init(
            .calendarJoining, "Auto Join Meetings",
            keywords: ["automatic", "start"]),
        .init(
            .calendarJoining, "Confirm before joining",
            keywords: ["ask", "prompt"]),
        .init(
            .calendarJoining, "Camera Preview",
            keywords: ["webcam", "mirror", "video", "check"]),
        .init(
            .calendarMenuBar, "Calendar in Menu Bar",
            keywords: ["status item", "menubar", "date"]),
        .init(
            .calendarMenuBar, "Show Upcoming Events",
            keywords: ["menubar", "next event", "title"]),
        .init(
            .calendarMenuBar, "Only show events with meetings",
            keywords: ["links", "filter", "menubar"]),
        .init(
            .calendarMenuBar, "Hide Current Event",
            keywords: ["started", "time left", "menubar"]),
        .init(
            group: .calendarCalendars, "Calendars",
            keywords: ["accounts", "sources", "choose", "icloud", "google"])
    ]

    private static let extensions: [SettingsSearchEntry] = [
        .init(
            pane: .extensions,
            keywords: ["raycast", "plugins", "store", "javascript"]),
        .init(
            .extensionsExtensions, "Enable extensions",
            keywords: ["raycast", "third party", "javascript"]),
        .init(
            group: .extensionsCompatibility, "Compatibility",
            keywords: ["supported", "unsupported", "raycast api"]),
        .init(
            group: .extensionsInstalled, "Installed extensions",
            keywords: ["library", "uninstall", "preferences", "appearance"]),
        .init(
            .extensionsInstall, "Search extensions",
            keywords: ["store", "browse", "install", "registry"]),
        .init(
            group: .extensionsInstall, "Registries",
            keywords: ["github", "source", "store"]),
        .init(
            .extensionsInstall, "Import from Raycast",
            keywords: ["migrate", "existing"]),
        .init(
            .extensionsInstall, "Add from folder",
            keywords: ["local", "develop", "sideload"]),
        .init(
            .extensionsStorage, "Leftover files",
            keywords: ["clean up", "disk", "reclaim", "cache"])
    ]

    private static let permissions: [SettingsSearchEntry] = [
        .init(
            pane: .permissions,
            keywords: ["privacy", "tcc", "access", "grant"]),
        .init(
            .permissionsAccessibility, "Accessibility",
            keywords: ["paste", "keystrokes", "privacy", "grant"]),
        .init(
            .permissionsCalendars, "Calendars",
            keywords: ["events", "privacy", "grant", "eventkit"])
    ]

    private static let backup: [SettingsSearchEntry] = [
        .init(
            pane: .backup,
            keywords: ["export", "import", "restore", "migrate", "raycast"]),
        .init(
            .backupExport, "Export Backup",
            keywords: ["save", "tinycast file", "archive"]),
        .init(
            .backupImport, "Backup File",
            keywords: ["restore", "choose", "tinycast file"]),
        .init(
            .backupImportFromRaycast, "Raycast Export",
            keywords: ["migrate", "rayconfig", "passphrase"])
    ]

    private static let about: [SettingsSearchEntry] = [
        .init(
            pane: .about,
            keywords: ["version", "licence", "license", "credits"]),
        .init(
            .aboutAbout, "Check for Updates",
            keywords: ["version", "upgrade", "release"]),
        .init(
            group: .aboutLinks, "Links",
            keywords: ["github", "source", "issues", "website"]),
        .init(
            .aboutLinks, "Support",
            keywords: ["donate", "sponsor", "funding"])
    ]
}
