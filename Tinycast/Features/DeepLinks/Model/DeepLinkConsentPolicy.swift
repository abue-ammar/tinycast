import Foundation

/// Which links from outside ask first: opening a Tinycast screen is harmless, acting elsewhere isn't.
enum DeepLinkConsentPolicy {
    static func requiresConsent(_ action: HotKeyAction) -> Bool {
        switch action {
        case .command(let id):
            requiresConsent(id)
        case .togglePalette, .settingsPane:
            false
        case .dictation, .app, .customCommand, .systemAction, .windowCommand, .windowLayout,
            .windowRoom, .customWindowSize, .quicklink, .quickAction, .appleShortcut, .snippet,
            .extensionCommand:
            true
        }
    }

    /// No `default`, so a new command has to be classed before it builds.
    private static func requiresConsent(_ id: CommandID) -> Bool {
        switch id {
        case .fixGrammar, .rewrite, .translate, .summarize, .pasteSequentially, .openCamera,
            .joinNextMeeting, .copyMeetingLink, .openInCalendar, .captureWindowLayout, .openInBrowser,
            .runShellCommand, .quit:
            true
        case .quickAI, .aiChat, .calculatorHistory, .clipboardHistory, .searchEmoji, .searchFiles,
            .searchMenuItems, .switchWindows, .switchWindowsBackwards, .createCustomCommand,
            .searchCustomCommands, .define, .mySchedule, .createEvent, .showNotes, .createNote,
            .searchNotes, .createWindowLayout, .switchRoom, .createRoom, .createQuicklink,
            .searchQuicklinks, .importQuicklinks, .exportQuicklinks, .searchSnippets, .createSnippet,
            .exportSettings, .importSettings, .importFromRaycast, .checkForUpdates, .settings, .about,
            .support:
            false
        }
    }
}
