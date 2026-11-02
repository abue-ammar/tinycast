import Foundation

/// Which links from outside ask first, and what Always Allow remembers of them.
enum DeepLinkConsentPolicy {
    /// Input always asks: text a page chose is one Return from running wherever it lands.
    static func requiresConsent(_ action: HotKeyAction, input: DeepLinkInput) -> Bool {
        !input.isEmpty || requiresConsent(action)
    }

    /// The row alone, or the row with the exact input, so a grant never covers other input.
    static func key(entryID: String, input: DeepLinkInput) -> String {
        // A snippet's ID is a path and may hold a `?`; encoded, the first `?` is always the split.
        let row = entryID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? entryID
        let query = input.percentEncodedQueryItems.map { "\($0.name)=\($0.value ?? "")" }
        return query.isEmpty ? row : row + "?" + query.joined(separator: "&")
    }

    /// The row and input a remembered key stands for; nil for one this build can't read.
    static func parts(ofKey key: String) -> (entryID: String, input: DeepLinkInput)? {
        let split = key.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let entryID = split.first.flatMap({ String($0).removingPercentEncoding }) else {
            return nil
        }
        var components = URLComponents()
        components.percentEncodedQuery = split.count == 2 ? String(split[1]) : nil
        guard let input = DeepLinkInput(queryItems: components.queryItems ?? []) else { return nil }
        return (entryID, input)
    }

    /// Opening a Tinycast screen is harmless; acting outside Tinycast is not.
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
