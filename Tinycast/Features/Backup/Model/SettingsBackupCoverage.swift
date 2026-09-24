import Foundation

/// What `SettingsBackup.SettingsData` carries, written out so a new setting has to be considered.
enum SettingsBackupCoverage {
    /// Each `SettingsData` field paired with the `AppSettings` key it mirrors.
    static let mirrored: [String: AppSettingsKey] = [
        "clipboardEnabled": .clipboardEnabled,
        "clipboardRetentionDays": .clipboardRetention,
        "clipboardDefaultAction": .clipboardDefaultAction,
        "clipboardDisabledApps": .clipboardDisabledApps,
        "hyperKey": .hyperKey,
        "hyperKeyIncludesShift": .hyperKeyIncludesShift,
        "hyperKeyQuickPress": .hyperKeyQuickPress,
        "emojiSkinTone": .emojiSkinTone,
        "emojiGridColumns": .emojiGridColumns,
        "popToRootSeconds": .popToRootTimeout,
        "escapeKeyBehavior": .escapeKeyBehavior,
        "appearance": .appearance,
        "calcNumberStyle": .calcNumberStyle,
        "interfaceSize": .interfaceSize,
        "compactMode": .compactMode,
        "showFavoritesInCompactMode": .showFavoritesInCompactMode,
        "searchScopes": .searchScopes,
        "launcherShowsSuggestions": .launcherShowsSuggestions,
        "rootSearchSensitivity": .rootSearchSensitivity,
        "openOnCursorScreen": .openOnCursorScreen,
        "paletteDraggable": .paletteDraggable,
        "fileSearchEnabled": .fileSearchEnabled,
        "fileSearchScopes": .fileSearchScopes,
        "fileSearchIgnorePatterns": .fileSearchIgnorePatterns,
        "notesEnabled": .notesEnabled,
        "notesRendersMarkdown": .notesRendersMarkdown,
        "notesShowsFormattingBar": .notesShowsFormattingBar,
        "customCommandsEnabled": .customCommandsEnabled,
        "customCommandsShowInLauncher": .customCommandsShowInLauncher,
        "snippetsShowInLauncher": .snippetsShowInLauncher,
        "navigationEnabled": .navigationEnabled,
        "menuSearchDisabledApps": .menuSearchDisabledApps,
        "menuSearchShowsAppleMenu": .menuSearchShowsAppleMenu,
        "windowManagementEnabled": .windowManagementEnabled,
        "windowManagementShowInLauncher": .windowManagementShowInLauncher,
        "windowGap": .windowGap,
        "windowCycle": .windowCycle,
        "windowLayoutsShowInLauncher": .windowLayoutsShowInLauncher,
        "quicklinksEnabled": .quicklinksEnabled,
        "quicklinksShowInLauncher": .quicklinksShowInLauncher,
        "quicklinkOpensNewWindow": .quicklinkOpensNewWindow,
        "quicklinkSelectionFallback": .quicklinkSelectionFallback,
        "quicklinkConfirmsBeforeDelete": .quicklinkConfirmsBeforeDelete,
        "appleShortcutsEnabled": .appleShortcutsEnabled,
        "extensionsShowInLauncher": .extensionsShowInLauncher,
        "calendarShowInLauncher": .calendarShowInLauncher,
        "calendarLauncherLimit": .calendarLauncherLimit,
        "calendarIncludesTomorrow": .calendarIncludesTomorrow,
        "joinWindowMinutes": .joinWindowMinutes,
        "autoJoinConfirms": .autoJoinConfirms,
        "menuBarEvents": .menuBarEvents,
        "calendarMenuBarDisplay": .calendarMenuBarDisplay,
        "menuBarLinkedEventsOnly": .menuBarLinkedEventsOnly,
        "calendarMenuBarHidesWhenEmpty": .calendarMenuBarHidesWhenEmpty,
        "hideCurrentEvent": .hideCurrentEvent,
        "supportReminders": .supportReminders
    ]

    /// The `SettingsData` fields no `AppSettings` key stands behind, and what they read instead.
    static let externallySourced: [String: String] = [
        "launchAtLogin": "Read from LaunchAtLogin, which owns the login item, not UserDefaults.",
        "showInMenuBar": "SettingsKey.showInMenuBar — shared with MenuBarExtra, not owned here."
    ]

    /// Keys kept out of a backup on purpose, each with the reason it has to stay out.
    static let deliberatelyExcluded: [String: String] = [
        AppSettingsKey.clipboardTextSearchEnabled.rawValue:
            "Background OCR is an opt-in processing choice on this Mac; a backup must not enable it.",
        AppSettingsKey.snippetsEnabled.rawValue:
            "Doubles as keyword-expansion consent; an import must not enable keystroke listening.",
        AppSettingsKey.extensionPackageManager.rawValue:
            "Names a tool on this Mac; the machine a backup lands on may not have it.",
        AppSettingsKey.extensionRegistries.rawValue:
            "A registry is a source of executable code; adding one has to be a deliberate act.",
        AppSettingsKey.extensionCustomSearchPaths.rawValue:
            "Machine-local toolchain paths; the Mac a backup lands on may not have them, or may have "
            + "something else there.",
        AppSettingsKey.extensionsEnabled.rawValue:
            "Doubles as consent to run third-party JavaScript; an import must not switch it on.",
        AppSettingsKey.palettePosition.rawValue:
            "Machine-local geometry: every entry names a display this Mac has, and no other one.",
        AppSettingsKey.autoSwitchInputSource.rawValue:
            "Names a keyboard input source installed on this Mac; another Mac may not have it.",
        AppSettingsKey.meetingBrowser.rawValue:
            "Names a browser installed on this Mac; another Mac may not have it.",
        AppSettingsKey.calendarEnabled.rawValue:
            "Doubles as consent to read your calendar; an import must not grant calendar access.",
        AppSettingsKey.autoJoinMeetings.rawValue:
            "Arms the app to open meeting links unattended; an import must not switch that on.",
        AppSettingsKey.cameraPreview.rawValue:
            "Turns the camera on before a meeting; an import must not grant that.",
        AppSettingsKey.aiEnabled.rawValue:
            "No other AI setting travels in a backup, so an import would arm a feature it cannot "
            + "configure.",
        AppSettingsKey.naturalCommandsEnabled.rawValue:
            "Permits typed queries to leave this Mac for TypeSafe, so an import must not grant that "
            + "network capability.",
        AppSettingsKey.aiInstalledProviders.rawValue:
            "Installed commands and their accounts belong to this Mac; an import must not enable "
            + "their discovery on another one.",
        AppSettingsKey.aiConnections.rawValue:
            "AI connection metadata stays on the Mac with the Keychain credentials it describes.",
        AppSettingsKey.aiDefaultModel.rawValue:
            "The default model names an external AI destination; importing must not choose one.",
        AppSettingsKey.aiWebSearch.rawValue:
            "Whether prompts may reach a search engine is a choice each Mac makes for itself.",
        AppSettingsKey.aiSystemPrompt.rawValue:
            "Standing instructions to a model are the one AI setting that changes every answer; an "
            + "import must not carry them onto another Mac unseen.",
        AppSettingsKey.aiSystemPromptEnabled.rawValue:
            "Governs whether a turn carries standing instructions at all, so it changes every answer "
            + "the same way the prompt it gates does.",
        AppSettingsKey.aiRetention.rawValue:
            "How long conversations survive is a decision about the chats on this Mac, and an import "
            + "must never arrive carrying an instruction to delete them.",
        AppSettingsKey.aiOpensTo.rawValue:
            "Whether chat reopens on an existing conversation depends on the history this Mac holds, "
            + "which no other Mac has.",
        AppSettingsKey.aiNewChatAfter.rawValue:
            "Paces the same decision as the setting it accompanies, against conversations that stay "
            + "on the Mac that had them.",
        AppSettingsKey.aiToolRounds.rawValue:
            "Decides how much a tool-driven reply may spend on this Mac's own connections; no other "
            + "AI setting travels, and an import must not raise a spending limit unasked.",
        AppSettingsKey.mcpEnabled.rawValue:
            "Doubles as consent to run third-party MCP servers, one of which is a local process; a "
            + "flag that grants a capability is never carried by a backup.",
        AppSettingsKey.mcpServers.rawValue:
            "An MCP server is a source of executable code and a destination for chat context, and "
            + "it is meaningless without the machine-local Keychain secrets it describes.",
        AppSettingsKey.quickActionsEnabled.rawValue:
            "Grants keystroke delivery into other apps through the Accessibility permission, and a "
            + "flag that grants a capability is never carried by a backup.",
        AppSettingsKey.quickActionModel.rawValue:
            "Names an external AI destination for text taken from whatever app is frontmost; an "
            + "import must not choose one.",
        AppSettingsKey.quickActionModelOverrides.rawValue:
            "Sends one action's text to its own AI destination, some keyed by actions that exist only "
            + "on the Mac that made them.",
        AppSettingsKey.quickActionPreviews.rawValue:
            "Says which actions may rewrite a document without showing the result first, which is a "
            + "decision each Mac makes about its own text.",
        AppSettingsKey.quickActionInstructions.rawValue:
            "Custom model instructions change transformed results and must not move unseen.",
        AppSettingsKey.quickActionLanguage.rawValue:
            "Follows the language the person at this Mac reads, not the one who wrote the backup."
    ]
}
