import Foundation

/// Where each settings.json key lives; exhaustive, so a new key fails to build until it is bound.
@MainActor
enum SettingsFileSchema {
    static func bindings(
        settings: AppSettings, ai: AISettingsStore, quickActions: QuickActionSettingsStore,
        windowManagement: WindowManagementSettingsFile
    ) -> [SettingsFileBinding] {
        var bindings: [SettingsFileBinding] = []
        for key in SettingsFileKey.allCases {
            bindings.append(
                binding(
                    for: key, settings: settings, ai: ai, quickActions: quickActions,
                    windowManagement: windowManagement))
        }
        return bindings
    }

    private static func binding(
        for key: SettingsFileKey, settings: AppSettings, ai: AISettingsStore,
        quickActions: QuickActionSettingsStore, windowManagement: WindowManagementSettingsFile
    ) -> SettingsFileBinding {
        func bind<Root: AnyObject, Value: SettingsFileValue>(
            _ root: Root, _ path: ReferenceWritableKeyPath<Root, Value>,
            accept: @escaping (Value) -> Value? = { $0 }
        ) -> SettingsFileBinding {
            SettingsFileBinding(key, root, path, accept: accept)
        }

        switch key {
        case .showInMenuBar: return bind(settings, \.showInMenuBar)
        case .automaticallyCheckForUpdates: return bind(settings, \.automaticallyCheckForUpdates)
        case .popToRootTimeout: return bind(settings, \.popToRootTimeout)
        case .escapeKeyBehavior: return bind(settings, \.escapeKeyBehavior)
        case .autoSwitchInputSource: return bind(settings, \.autoSwitchInputSourceID)
        case .supportReminders: return bind(settings, \.supportRemindersEnabled)
        case .appearance: return bind(settings, \.appearance)
        case .interfaceSize: return bind(settings, \.interfaceSize)
        case .compactMode: return bind(settings, \.compactMode)
        case .showFavoritesInCompactMode: return bind(settings, \.showFavoritesInCompactMode)
        case .openOnCursorScreen: return bind(settings, \.openOnCursorScreen)
        case .paletteDraggable: return bind(settings, \.paletteDraggable)
        case .hyperKey: return bind(settings, \.hyperKey)
        case .hyperKeyIncludesShift: return bind(settings, \.hyperKeyIncludesShift)
        case .hyperKeyQuickPress: return bind(settings, \.hyperKeyQuickPress)
        case .calcNumberStyle: return bind(settings, \.calcNumberStyle)
        case .launcherShowsSuggestions: return bind(settings, \.launcherShowsSuggestions)
        case .rootSearchSensitivity: return bind(settings, \.rootSearchSensitivity)
        case .searchScopes: return bind(settings, \.searchScopes) { SearchScopes.normalize($0) }
        case .customCommandsEnabled: return bind(settings, \.customCommandsEnabled)
        case .customCommandsShowInLauncher: return bind(settings, \.customCommandsShowInLauncher)
        case .quicklinksEnabled: return bind(settings, \.quicklinksEnabled)
        case .quicklinksShowInLauncher: return bind(settings, \.quicklinksShowInLauncher)
        case .quicklinkOpensNewWindow: return bind(settings, \.quicklinkOpensNewWindow)
        case .quicklinkSelectionFallback: return bind(settings, \.quicklinkSelectionFallback)
        case .quicklinkConfirmsBeforeDelete: return bind(settings, \.quicklinkConfirmsBeforeDelete)
        case .appleShortcutsEnabled: return bind(settings, \.appleShortcutsEnabled)
        case .aiEnabled: return bind(settings, \.aiEnabled)
        case .aiWebSearch: return bind(ai, \.webSearchEnabled)
        case .aiSystemPrompt: return bind(ai, \.systemPrompt)
        case .aiSystemPromptEnabled: return bind(ai, \.systemPromptEnabled)
        case .aiRetention: return bind(ai, \.retention)
        case .aiOpensTo: return bind(ai, \.opensTo)
        case .aiNewChatAfter: return bind(ai, \.newChatAfter)
        case .aiToolRounds: return bind(ai, \.toolRounds)
        case .quickActionLanguage: return bind(quickActions, \.settings.targetLanguage)
        case .fileSearchEnabled: return bind(settings, \.fileSearchEnabled)
        case .fileSearchScopes: return bind(settings, \.fileSearchScopes)
        case .fileSearchIgnorePatterns: return bind(settings, \.fileSearchIgnorePatterns)
        case .notesEnabled: return bind(settings, \.notesEnabled)
        case .notesRendersMarkdown: return bind(settings, \.notesRendersMarkdown)
        case .notesShowsFormattingBar: return bind(settings, \.notesShowsFormattingBar)
        case .notesFolder: return bind(settings, \.notesFolder, accept: folder)
        case .dictationMode: return bind(settings, \.dictationMode)
        case .dictationModel: return bind(settings, \.dictationModel)
        case .dictationMicrophone: return bind(settings, \.dictationMicrophone)
        case .dictationDestination: return bind(settings, \.dictationDestination)
        case .dictationAdaptsCapitalization: return bind(settings, \.dictationAdaptsCapitalization)
        case .dictationIdleRelease: return bind(settings, \.dictationIdleRelease)
        case .dictationLanguage:
            return bind(settings, \.dictationLanguage) { language in
                guard let language else { return .some(nil) }
                return DictationLanguage(rawValue: language) == nil ? nil : .some(language)
            }
        case .snippetsShowInLauncher: return bind(settings, \.snippetsShowInLauncher)
        case .snippetsFolder: return bind(settings, \.snippetsFolder, accept: folder)
        case .navigationEnabled: return bind(settings, \.navigationEnabled)
        case .menuSearchShowsAppleMenu: return bind(settings, \.menuSearchShowsAppleMenu)
        case .menuSearchDisabledApps: return bind(settings, \.menuSearchDisabledApps)
        case .windowManagementEnabled: return bind(settings, \.windowManagementEnabled)
        case .windowManagementShowInLauncher:
            return bind(settings, \.windowManagementShowInLauncher)
        case .windowGap:
            return bind(settings, \.windowGap) {
                WindowPlacementEngine.gapRange.contains($0) ? $0 : nil
            }
        case .windowCycle: return bind(settings, \.windowCycle)
        case .windowLayoutsShowInLauncher: return bind(settings, \.windowLayoutsShowInLauncher)
        case .windowRoomsShowInLauncher: return bind(settings, \.windowRoomsShowInLauncher)
        case .windowShortcuts: return windowManagement.commandShortcutsBinding(for: key)
        case .customWindowSizes: return windowManagement.customSizesBinding(for: key)
        case .windowLayouts: return windowManagement.layoutsBinding(for: key)
        case .windowRooms: return windowManagement.roomsBinding(for: key)
        case .clipboardEnabled: return bind(settings, \.clipboardEnabled)
        case .clipboardRetention: return bind(settings, \.clipboardRetention)
        case .clipboardDefaultAction: return bind(settings, \.clipboardDefaultAction)
        case .clipboardDisabledApps: return bind(settings, \.clipboardDisabledApps)
        case .emojiSkinTone: return bind(settings, \.emojiSkinTone)
        case .emojiGridColumns: return bind(settings, \.emojiGridColumns)
        case .calendarShowInLauncher: return bind(settings, \.calendarShowInLauncher)
        case .calendarLauncherLimit: return bind(settings, \.calendarLauncherLimit)
        case .calendarSpan: return bind(settings, \.calendarSpan)
        case .joinWindowMinutes: return bind(settings, \.joinWindowMinutes)
        case .autoJoinConfirms: return bind(settings, \.autoJoinConfirms)
        case .meetingBrowser: return bind(settings, \.meetingBrowserBundleID)
        case .calendarMenuBarDisplay: return bind(settings, \.calendarMenuBarDisplay)
        case .menuBarEvents: return bind(settings, \.menuBarEvents)
        case .menuBarLinkedEventsOnly: return bind(settings, \.menuBarLinkedEventsOnly)
        case .calendarMenuBarHidesWhenEmpty: return bind(settings, \.calendarMenuBarHidesWhenEmpty)
        case .hideCurrentEvent: return bind(settings, \.hideCurrentEvent)
        case .extensionsShowInLauncher: return bind(settings, \.extensionsShowInLauncher)
        }
    }

    /// A folder is absolute or under `~/`; null puts it back in Application Support.
    private static func folder(_ path: String?) -> String?? {
        guard let path else { return .some(nil) }
        return AppPaths.isFolderPath(path) ? path : nil
    }
}

extension PopToRootTimeout: SettingsFileRawValue {}
extension EscapeKeyBehavior: SettingsFileRawValue {}
extension AppAppearance: SettingsFileRawValue {}
extension InterfaceSize: SettingsFileRawValue {}
extension HyperKeyPhysicalKey: SettingsFileRawValue {}
extension HyperKeyQuickPress: SettingsFileRawValue {}
extension CalcNumberStyle: SettingsFileRawValue {}
extension SearchSensitivity: SettingsFileRawValue {}
extension QuicklinkSelectionFallback: SettingsFileRawValue {}
extension WindowCycle: SettingsFileRawValue {}
extension ClipboardDefaultAction: SettingsFileRawValue {}
extension EmojiSkinTone: SettingsFileRawValue {}
extension EmojiGridColumns: SettingsFileRawValue {}
extension DictationModel: SettingsFileRawValue {}
extension DictationMode: SettingsFileRawValue {}
extension DictationDestination: SettingsFileRawValue {}
extension DictationIdleRelease: SettingsFileRawValue {}
extension JoinWindow: SettingsFileRawValue {}

extension ClipboardRetention: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .year: 365
        case .forever: "forever"
        }
    }
}

extension AIRetention: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .forever: "forever"
        }
    }
}

extension AIOpensTo: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .recent: "recent"
        case .newConversation: "newConversation"
        }
    }
}

extension AINewChatAfter: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .twoMinutes: 2
        case .fiveMinutes: 5
        case .tenMinutes: 10
        case .thirtyMinutes: 30
        case .never: "never"
        }
    }
}

extension AIToolRounds: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .ten: 10
        case .twentyFive: 25
        case .fifty: 50
        case .hundred: 100
        case .unlimited: "unlimited"
        }
    }
}

extension CalendarLauncherLimit: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .one: 1
        case .three: 3
        case .five: 5
        case .all: "all"
        }
    }
}

extension MeetingSpan: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .today: "today"
        case .todayAndTomorrow: "todayAndTomorrow"
        case .nextSevenDays: "nextSevenDays"
        }
    }
}

extension CalendarMenuBarDisplay: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .disabled: "disabled"
        case .meetingIcon: "meetingIcon"
        case .meetingTitle: "meetingTitle"
        }
    }
}

extension MenuBarEvents: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .today: "today"
        case .two: 2
        case .five: 5
        case .ten: 10
        case .thirty: 30
        }
    }
}

extension HideCurrentEvent: SettingsFileToken {
    var settingsToken: SettingsFileJSON {
        switch self {
        case .dontHide: "never"
        case .automatically: 0
        case .afterFive: 5
        case .afterTen: 10
        case .afterThirty: 30
        }
    }
}
