import Foundation

/// Which category carries each setting; nil keeps it on this Mac. Exhaustive by construction.
enum SyncSettingScope {
    /// Open at Login has no settings.json key: `LaunchAtLogin` owns it, not `UserDefaults`.
    static let launchAtLoginKey = "general.launchAtLogin"

    static func category(of key: String) -> SyncCategory? {
        if key == launchAtLoginKey { return .launchAtLogin }
        return SettingsFileKey(rawValue: key).flatMap(category)
    }

    static var syncedKeys: [String] {
        [launchAtLoginKey] + SettingsFileKey.allCases.filter { category(of: $0) != nil }.map(\.rawValue)
    }

    static func category(of key: SettingsFileKey) -> SyncCategory? {
        switch key {
        // A feature's switch is enabled per Mac, and a folder, scope or device names this Mac.
        case .language, .applicationsEnabled, .searchScopes, .systemSettingsEnabled,
            .systemActionsEnabled, .builtInCommandsEnabled, .customCommandsEnabled,
            .quicklinksEnabled, .appleShortcutsEnabled, .aiEnabled, .dictationModel,
            .dictationMicrophone, .fileSearchEnabled, .fileSearchScopes, .notesEnabled,
            .notesFolder, .snippetsFolder, .navigationEnabled, .windowManagementEnabled,
            .clipboardEnabled:
            nil
        case .showInMenuBar: .showInMenuBar
        case .appearance, .animationsEnabled: .appearance
        case .interfaceSize: .interfaceSize
        case .compactMode, .compactBarCommands: .windowMode
        case .aiSystemPrompt, .aiSystemPromptEnabled: .aiCommands
        case .aiRetention: .aiChats
        case .dictationMode, .dictationPlaysSounds, .dictationDestination,
            .dictationAdaptsCapitalization, .dictationLiveInsertion, .dictationIdleRelease,
            .dictationLanguage:
            .dictation
        case .customWindowSizes, .windowLayouts, .windowRooms: .windowLayouts
        case .launcherShortcut, .hyperKey, .hyperKeyIncludesShift, .hyperKeyQuickPress,
            .hyperKeySecureInputCompatibility, .applications, .systemSettings, .systemActions,
            .builtInCommands, .quicklinkCommands, .aiCommands, .quickActionCommands,
            .dictationShortcut, .fileSearchCommands, .notesCommands, .snippetsCommands,
            .navigationCommands, .windowShortcuts, .windowAliases, .windowManagementCommands,
            .clipboardCommands, .emojiCommands, .calendarCommands:
            .hotkeysAndAliases
        case .automaticallyCheckForUpdates, .popToRootTimeout, .escapeKeyBehavior,
            .autoSwitchInputSource, .supportReminders, .openOnCursorScreen, .paletteDraggable,
            .calcNumberStyle, .launcherShowsSuggestions, .rootSearchSensitivity,
            .customCommandsShowInLauncher, .quicklinksShowInLauncher, .quicklinkOpensNewWindow,
            .quicklinkPassesSelectedText, .quicklinkConfirmsBeforeDelete, .aiWebSearch,
            .aiChoices, .aiExpandsReasoning, .aiOpensTo, .aiNewChatAfter, .aiToolRounds,
            .quickActionLanguage, .fileSearchIncludesHiddenFiles, .fileSearchIgnorePatterns,
            .fileSearchRemovedDefaultPatterns, .fileSearchShowInLauncher, .notesRendersMarkdown,
            .notesShowsFormattingBar, .notesShowsInMenuBar, .snippetsShowInLauncher,
            .snippetDefaultAction, .menuSearchShowsAppleMenu, .menuSearchDisabledApps,
            .windowManagementShowInLauncher, .windowGap, .windowCycle, .windowWrapsDisplays,
            .windowKeepsProportions, .windowLayoutsShowInLauncher, .windowRoomsShowInLauncher,
            .clipboardRetention, .clipboardDefaultAction, .clipboardDisabledApps, .emojiSkinTone,
            .emojiGridColumns, .calendarShowInLauncher, .calendarLauncherLimit, .calendarSpan,
            .joinWindowMinutes, .autoJoinConfirms, .autoJoinNamedProvidersOnly, .meetingBrowser,
            .calendarMenuBarDisplay, .menuBarEvents, .menuBarLinkedEventsOnly,
            .calendarMenuBarHidesWhenEmpty, .hideCurrentEvent, .extensionsShowInLauncher:
            .otherSettings
        }
    }
}
