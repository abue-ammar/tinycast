import Foundation

/// One searchable place in Settings: a pane, or a row inside one of its `Form` sections.
struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    let tab: SettingsTab
    /// The `Section` header the row sits under; nil for the pane itself.
    var section: String?
    let title: String
    /// Words a user might type that the visible title doesn't contain.
    var keywords: [String] = []

    var id: String { "\(tab.title)/\(section ?? "")/\(title)" }

    /// The result row's second line — "General", or "General › Hyper Key".
    var breadcrumb: String {
        guard let section, section != tab.title else { return tab.title }
        return "\(tab.title) › \(section)"
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
        return band + titleScore + (entry.section == nil ? 500_000 : 0)
    }

    // MARK: - The index
    // Pane order, then section order within a pane, so this reads as a table of contents.

    static let entries: [SettingsSearchEntry] =
        general + applications + systemSettings
        + systemActions + commands + quicklinks + fallbacks + ai + quickActions + fileSearch + notes
        + snippets + windowManagement + clipboard + emoji + calendar + extensions + permissions
        + backup + about

    private static let general: [SettingsSearchEntry] = [
        .init(tab: .general, title: "General", keywords: ["preferences", "settings"]),
        .init(
            tab: .general, section: "Global Shortcuts", title: "App Launcher",
            keywords: ["hotkey", "shortcut", "summon", "palette"]),
        .init(
            tab: .general, section: "Search", title: "Learned ranking",
            keywords: ["reset", "history", "order", "privacy"]),
        .init(
            tab: .general, section: "Hyper Key", title: "Hyper Key",
            keywords: ["modifier", "remap", "caps lock", "capslock"]),
        .init(
            tab: .general, section: "Hyper Key", title: "Quick Press",
            keywords: ["tap", "escape", "single press"]),
        .init(
            tab: .general, section: "Hyper Key", title: "Include Shift (⇧)",
            keywords: ["modifier", "chord"]),
        .init(
            tab: .general, section: "Appearance", title: "Theme",
            keywords: ["dark", "light", "mode", "appearance"]),
        .init(
            tab: .general, section: "Appearance", title: "Compact mode",
            keywords: ["slim", "search bar", "small"]),
        .init(
            tab: .general, section: "Appearance", title: "Show favorites in compact mode",
            keywords: ["pinned", "apps", "compact"]),
        .init(
            tab: .general, section: "Appearance", title: "Follow the cursor across displays",
            keywords: ["monitor", "screen", "pointer", "multi display"]),
        .init(
            tab: .general, section: "Appearance", title: "Drag to reposition",
            keywords: ["move", "position", "window"]),
        .init(
            tab: .general, section: "General", title: "Launch at login",
            keywords: ["startup", "login item", "start", "boot"]),
        .init(
            tab: .general, section: "General", title: "Show in menu bar",
            keywords: ["menubar", "status item", "icon", "hide"]),
        .init(
            tab: .general, section: "General", title: "Pop to Root Search",
            keywords: ["reset", "timeout", "back"]),
        .init(
            tab: .general, section: "General", title: "Auto-switch input source",
            keywords: ["keyboard", "layout", "language", "abc"])
    ]

    private static let applications: [SettingsSearchEntry] = [
        .init(tab: .applications, title: "Applications", keywords: ["apps", "index", "launcher"]),
        .init(
            tab: .applications, section: "Search Scopes", title: "Search Scopes",
            keywords: ["folders", "indexed", "locations", "add folder"]),
        .init(
            tab: .applications, section: "Applications", title: "Enable Applications",
            keywords: ["hide apps", "visibility"]),
        .init(
            tab: .applications, section: "Applications", title: "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "per app", "hide"])
    ]

    private static let systemSettings: [SettingsSearchEntry] = [
        .init(
            tab: .systemSettings, title: "System Settings",
            keywords: ["panes", "preferences", "macos"]),
        .init(
            tab: .systemSettings, section: "System Settings", title: "Enable System Settings",
            keywords: ["hide panes", "visibility"])
    ]

    private static let systemActions: [SettingsSearchEntry] = [
        .init(
            tab: .systemActions, title: "System Actions",
            keywords: ["sleep", "lock", "restart", "shut down", "empty trash"]),
        .init(
            tab: .systemActions, section: "System Actions", title: "Enable System Actions",
            keywords: ["hide", "visibility"])
    ]

    private static let commands: [SettingsSearchEntry] = [
        .init(
            tab: .commands, title: "Commands",
            keywords: ["custom", "script", "shell", "terminal"]),
        .init(
            tab: .commands, section: "Commands", title: "Enable Commands",
            keywords: ["hide", "visibility"]),
        .init(
            tab: .commands, section: "Custom Commands", title: "Enable custom commands",
            keywords: ["script", "shell"]),
        .init(
            tab: .commands, section: "Custom Commands", title: "Add Custom Command",
            keywords: ["new", "script", "shell", "shortcut"])
    ]

    private static let quicklinks: [SettingsSearchEntry] = [
        .init(tab: .quicklinks, title: "Quicklinks", keywords: ["url", "bookmark", "link"]),
        .init(
            tab: .quicklinks, section: "Quicklinks", title: "Enable quicklinks",
            keywords: ["url", "bookmark"]),
        .init(
            tab: .quicklinks, section: "Quicklinks", title: "Add Quicklink",
            keywords: ["new", "url", "bookmark", "alias"]),
        .init(
            tab: .quicklinks, section: "Behaviour", title: "Open in a new window",
            keywords: ["browser", "tab"]),
        .init(
            tab: .quicklinks, section: "Behaviour", title: "When there's no selected text",
            keywords: ["selection", "fallback", "placeholder"]),
        .init(
            tab: .quicklinks, section: "Behaviour", title: "Confirm before deleting",
            keywords: ["ask", "delete", "prompt"]),
        .init(
            tab: .quicklinks, section: "Import & Export", title: "Import quicklinks",
            keywords: ["json", "restore"]),
        .init(
            tab: .quicklinks, section: "Import & Export", title: "Export quicklinks",
            keywords: ["json", "backup"])
    ]

    private static let fallbacks: [SettingsSearchEntry] = [
        .init(
            tab: .fallbacks, title: "Fallbacks",
            keywords: ["no results", "empty", "search web", "order"])
    ]

    private static let ai: [SettingsSearchEntry] = [
        .init(tab: .ai, title: "AI", keywords: ["chat", "llm", "model", "openai", "anthropic"]),
        .init(tab: .ai, section: "AI", title: "Enable AI", keywords: ["chat", "llm"]),
        .init(
            tab: .ai, section: "Default", title: "Default model",
            keywords: ["llm", "gpt", "claude"]),
        .init(
            tab: .ai, section: "Default", title: "Reasoning effort",
            keywords: ["thinking", "chatgpt"]),
        .init(tab: .ai, section: "Chat", title: "Web search", keywords: ["browse", "internet"]),
        .init(
            tab: .ai, section: "Conversations", title: "Opens to",
            keywords: ["new chat", "last", "summon"]),
        .init(
            tab: .ai, section: "Conversations", title: "Start a new conversation after",
            keywords: ["idle", "timeout", "fresh"]),
        .init(
            tab: .ai, section: "Conversations", title: "Keep conversations",
            keywords: ["retention", "delete", "history", "privacy"]),
        .init(
            tab: .ai, section: "System prompt", title: "Send a system prompt",
            keywords: ["instructions", "persona"]),
        .init(
            tab: .ai, section: "ChatGPT Subscription", title: "ChatGPT Subscription",
            keywords: ["sign in", "connect", "plus", "codex", "openai"]),
        .init(
            tab: .ai, section: "API Connections", title: "Add API Connection",
            keywords: ["key", "provider", "openai", "anthropic", "ollama", "base url"]),
        .init(
            tab: .ai, section: "MCP Servers", title: "Enable MCP servers",
            keywords: ["tools", "model context protocol"]),
        .init(
            tab: .ai, section: "MCP Servers", title: "Add MCP Server",
            keywords: ["tools", "model context protocol", "stdio"]),
        .init(
            tab: .ai, section: "Commands", title: "AI commands",
            keywords: ["shortcut", "launcher", "chat"])
    ]

    private static let quickActions: [SettingsSearchEntry] = [
        .init(
            tab: .quickActions, title: "Quick Actions",
            keywords: ["selected text", "rewrite", "translate", "summarize"]),
        .init(
            tab: .quickActions, section: "Quick Actions", title: "Enable Quick Actions",
            keywords: ["selected text", "accessibility"]),
        .init(
            tab: .quickActions, section: "Actions", title: "Actions",
            keywords: ["shortcut", "replace", "preview", "customize"]),
        .init(
            tab: .quickActions, section: "Model", title: "Model",
            keywords: ["llm", "ai", "default"]),
        .init(
            tab: .quickActions, section: "Translate", title: "Translate to",
            keywords: ["language", "locale"])
    ]

    private static let fileSearch: [SettingsSearchEntry] = [
        .init(
            tab: .fileSearch, title: "File Search",
            keywords: ["spotlight", "files", "folders", "find"]),
        .init(
            tab: .fileSearch, section: "File Search", title: "Enable File Search",
            keywords: ["spotlight", "index"]),
        .init(
            tab: .fileSearch, section: "Commands", title: "File search commands",
            keywords: ["shortcut", "launcher"]),
        .init(
            tab: .fileSearch, section: "Search Scopes", title: "Search Scopes",
            keywords: ["folders", "locations", "home", "add folder"]),
        .init(
            tab: .fileSearch, section: "Ignore Patterns", title: "Ignore Patterns",
            keywords: ["exclude", "glob", "node_modules", "skip"])
    ]

    private static let notes: [SettingsSearchEntry] = [
        .init(tab: .notes, title: "Notes", keywords: ["markdown", "scratchpad", "floating"]),
        .init(
            tab: .notes, section: "Notes", title: "Enable Notes",
            keywords: ["markdown", "scratchpad"]),
        .init(
            tab: .notes, section: "Commands", title: "Notes commands",
            keywords: ["shortcut", "new note", "search notes"])
    ]

    private static let snippets: [SettingsSearchEntry] = [
        .init(
            tab: .snippets, title: "Snippets",
            keywords: ["expansion", "keyword", "text replacement", "template"]),
        .init(
            tab: .snippets, section: "Snippets", title: "Enable snippets",
            keywords: ["expansion", "keystrokes", "accessibility"]),
        .init(
            tab: .snippets, section: "Global Shortcut", title: "Search Snippets",
            keywords: ["hotkey", "browser"]),
        .init(
            tab: .snippets, section: "Library", title: "New Snippet",
            keywords: ["add", "keyword", "expansion"]),
        .init(
            tab: .snippets, section: "Library", title: "Snippets Folder",
            keywords: ["reveal", "finder", "markdown", "files"])
    ]

    private static let windowManagement: [SettingsSearchEntry] = [
        .init(
            tab: .windowManagement, title: "Window Management",
            keywords: ["tile", "halves", "thirds", "maximize", "snap"]),
        .init(
            tab: .windowManagement, section: "Window Management",
            title: "Enable window management", keywords: ["tile", "accessibility"]),
        .init(
            tab: .windowManagement, section: "Options", title: "Cycle sizes on repeat",
            keywords: ["repeat", "thirds", "halves"]),
        .init(
            tab: .windowManagement, section: "Options", title: "Gap between windows",
            keywords: ["padding", "spacing", "margin", "points"]),
        .init(
            tab: .windowManagement, section: "Options", title: "Window commands",
            keywords: ["shortcut", "left half", "maximize", "center"])
    ]

    private static let clipboard: [SettingsSearchEntry] = [
        .init(
            tab: .clipboard, title: "Clipboard",
            keywords: ["paste", "history", "copy", "pasteboard"]),
        .init(
            tab: .clipboard, section: "Global Shortcuts", title: "Clipboard History",
            keywords: ["hotkey", "paste", "browser"]),
        .init(
            tab: .clipboard, section: "History", title: "Keep history for",
            keywords: ["retention", "delete", "privacy", "expire"]),
        .init(
            tab: .clipboard, section: "Disabled Applications", title: "Disabled Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy"]),
        .init(
            tab: .clipboard, section: "Disabled Applications", title: "Clear history",
            keywords: ["delete", "erase", "wipe"])
    ]

    private static let emoji: [SettingsSearchEntry] = [
        .init(
            tab: .emoji, title: "Emoji & Symbols",
            keywords: ["picker", "character", "unicode", "smiley"]),
        .init(
            tab: .emoji, section: "Global Shortcuts", title: "Emoji & Symbols",
            keywords: ["hotkey", "picker"]),
        .init(
            tab: .emoji, section: "Appearance", title: "Emoji Skin Tone",
            keywords: ["colour", "color", "fitzpatrick", "default"])
    ]

    private static let calendar: [SettingsSearchEntry] = [
        .init(
            tab: .calendar, title: "Calendar",
            keywords: ["meetings", "events", "zoom", "join", "schedule"]),
        .init(
            tab: .calendar, section: "Calendar", title: "Join meetings from Tinycast",
            keywords: ["zoom", "meet", "teams", "permission"]),
        .init(
            tab: .calendar, section: "Schedule", title: "Upcoming meetings in launcher",
            keywords: ["count", "limit", "events"]),
        .init(
            tab: .calendar, section: "Schedule", title: "Include Tomorrow's Events",
            keywords: ["next day", "range"]),
        .init(
            tab: .calendar, section: "Joining", title: "Show the join card",
            keywords: ["hud", "timing", "early", "reminder"]),
        .init(
            tab: .calendar, section: "Joining", title: "Auto Join Meetings",
            keywords: ["automatic", "start"]),
        .init(
            tab: .calendar, section: "Joining", title: "Confirm before joining",
            keywords: ["ask", "prompt"]),
        .init(
            tab: .calendar, section: "Joining", title: "Camera Preview",
            keywords: ["webcam", "mirror", "video", "check"]),
        .init(
            tab: .calendar, section: "Menu Bar", title: "Calendar in Menu Bar",
            keywords: ["status item", "menubar", "date"]),
        .init(
            tab: .calendar, section: "Menu Bar", title: "Show Upcoming Events",
            keywords: ["menubar", "next event", "title"]),
        .init(
            tab: .calendar, section: "Menu Bar", title: "Only show events with meetings",
            keywords: ["links", "filter", "menubar"]),
        .init(
            tab: .calendar, section: "Menu Bar", title: "Hide Current Event",
            keywords: ["started", "time left", "menubar"]),
        .init(
            tab: .calendar, section: "Calendars", title: "Calendars",
            keywords: ["accounts", "sources", "choose", "icloud", "google"])
    ]

    private static let extensions: [SettingsSearchEntry] = [
        .init(
            tab: .extensions, title: "Extensions",
            keywords: ["raycast", "plugins", "store", "javascript"]),
        .init(
            tab: .extensions, section: "Extensions", title: "Enable extensions",
            keywords: ["raycast", "third party", "javascript"]),
        .init(
            tab: .extensions, section: "Compatibility", title: "Compatibility",
            keywords: ["supported", "unsupported", "raycast api"]),
        .init(
            tab: .extensions, section: "Installed", title: "Installed extensions",
            keywords: ["library", "uninstall", "preferences", "appearance"]),
        .init(
            tab: .extensions, section: "Install", title: "Search extensions",
            keywords: ["store", "browse", "install", "registry"]),
        .init(
            tab: .extensions, section: "Install", title: "Registries",
            keywords: ["github", "source", "store"]),
        .init(
            tab: .extensions, section: "Install", title: "Import from Raycast",
            keywords: ["migrate", "existing"]),
        .init(
            tab: .extensions, section: "Install", title: "Add from folder",
            keywords: ["local", "develop", "sideload"]),
        .init(
            tab: .extensions, section: "Storage", title: "Leftover files",
            keywords: ["clean up", "disk", "reclaim", "cache"])
    ]

    private static let permissions: [SettingsSearchEntry] = [
        .init(
            tab: .permissions, title: "Permissions",
            keywords: ["privacy", "tcc", "access", "grant"]),
        .init(
            tab: .permissions, section: "Accessibility", title: "Accessibility",
            keywords: ["paste", "keystrokes", "privacy", "grant"]),
        .init(
            tab: .permissions, section: "Calendars", title: "Calendars",
            keywords: ["events", "privacy", "grant", "eventkit"])
    ]

    private static let backup: [SettingsSearchEntry] = [
        .init(
            tab: .backup, title: "Backup",
            keywords: ["export", "import", "restore", "migrate", "raycast"]),
        .init(
            tab: .backup, section: "Export", title: "Export Backup",
            keywords: ["save", "tinycast file", "archive"]),
        .init(
            tab: .backup, section: "Import", title: "Backup File",
            keywords: ["restore", "choose", "tinycast file"]),
        .init(
            tab: .backup, section: "Import from Raycast", title: "Raycast Export",
            keywords: ["migrate", "rayconfig", "passphrase"])
    ]

    private static let about: [SettingsSearchEntry] = [
        .init(
            tab: .about, title: "About",
            keywords: ["version", "licence", "license", "credits"]),
        .init(
            tab: .about, section: "About", title: "Check for Updates",
            keywords: ["version", "upgrade", "release"]),
        .init(
            tab: .about, section: "Links", title: "Links",
            keywords: ["github", "source", "issues", "website"]),
        .init(
            tab: .about, section: "Links", title: "Support",
            keywords: ["donate", "sponsor", "funding"])
    ]
}
