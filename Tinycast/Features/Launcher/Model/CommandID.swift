import Foundation

/// Built-in launcher actions, surfaced alongside the user-authored ones.
enum CommandID: String, CaseIterable, Sendable {
    case aiChat = "command:ai-chat"
    case fixGrammar = "command:fix-grammar"
    case rewrite = "command:rewrite"
    case translate = "command:translate"
    case summarize = "command:summarize"
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case searchEmoji = "command:search-emoji"
    case searchFiles = "command:search-files"
    case openInBrowser = "command:open-in-browser"
    case runShellCommand = "command:run-shell-command"
    case joinNextMeeting = "command:join-next-meeting"
    case copyMeetingLink = "command:copy-meeting-link"
    case mySchedule = "command:my-schedule"
    case openInCalendar = "command:open-in-calendar"
    case createEvent = "command:create-event"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createQuicklink = "command:create-quicklink"
    case searchQuicklinks = "command:search-quicklinks"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case importQuicklinks = "command:import-quicklinks"
    case exportQuicklinks = "command:export-quicklinks"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case checkForUpdates = "command:check-for-updates"
    case settings = "command:settings"
    case about = "command:about"
    case support = "command:support"
    case quit = "command:quit"

    var name: String {
        switch self {
        case .aiChat: return "AI Chat"
        case .fixGrammar: return QuickAction.fixGrammar.title
        case .rewrite: return QuickAction.rewrite.title
        case .translate: return QuickAction.translate.title
        case .summarize: return QuickAction.summarize.title
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .searchFiles: return "Search Files"
        case .openInBrowser: return "Open in Browser"
        case .runShellCommand: return "Run Shell Command"
        case .joinNextMeeting: return "Join Next Meeting"
        case .copyMeetingLink: return "Copy Meeting Link"
        case .mySchedule: return "My Schedule"
        case .openInCalendar: return "Open in Calendar"
        case .createEvent: return "Create Event"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createQuicklink: return "Create Quicklink"
        case .searchQuicklinks: return "Search Quicklinks"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .importQuicklinks: return "Import Quicklinks"
        case .exportQuicklinks: return "Export Quicklinks"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .importFromRaycast: return "Import from Raycast"
        case .checkForUpdates: return "Check for Updates"
        case .settings: return "Settings"
        case .about: return "About Tinycast"
        case .support: return "Support Tinycast"
        case .quit: return "Quit Tinycast"
        }
    }

    var sfSymbol: String {
        switch self {
        case .aiChat: return "sparkles"
        case .fixGrammar: return QuickAction.fixGrammar.symbol
        case .rewrite: return QuickAction.rewrite.symbol
        case .translate: return QuickAction.translate.symbol
        case .summarize: return QuickAction.summarize.symbol
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .searchEmoji: return "face.smiling"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .openInBrowser: return "globe"
        case .runShellCommand: return "terminal"
        case .joinNextMeeting: return "video.fill"
        case .copyMeetingLink: return "link"
        case .mySchedule: return "calendar"
        case .openInCalendar: return "calendar.badge.clock"
        case .createEvent: return "calendar.badge.plus"
        case .showNotes: return "text.page"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createQuicklink: return "link.badge.plus"
        case .searchQuicklinks: return Quicklink.sfSymbol
        case .searchSnippets: return "curlybraces"
        case .createSnippet: return "plus.rectangle.on.rectangle"
        case .importQuicklinks: return "square.and.arrow.down"
        case .exportQuicklinks: return "square.and.arrow.up"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .checkForUpdates: return "arrow.down.circle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .support: return "heart"
        case .quit: return "power"
        }
    }

    /// Exhaustive over `QuickAction`, so a fifth cannot reach the launcher without a row here.
    init(_ action: QuickAction) {
        switch action {
        case .fixGrammar: self = .fixGrammar
        case .rewrite: self = .rewrite
        case .translate: self = .translate
        case .summarize: self = .summarize
        }
    }

    /// Query-driven: the typed text is their input, so they are built where offered, never listed.
    var isQueryDriven: Bool {
        self == .openInBrowser || self == .runShellCommand
    }

    /// A chord carries no query, and none should be able to terminate the app outright.
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
