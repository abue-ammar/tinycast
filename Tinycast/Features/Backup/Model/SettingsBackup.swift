import Foundation

/// A readable configuration snapshot; every field is optional, so an import merges.
struct SettingsBackup: Codable {

    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    var quicklinks: [Quicklink]?
    var windowLayouts: [WindowLayout]?
    var windowRooms: [Room]?
    var customWindowSizes: [CustomWindowSize]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?
    var launcherAliases: [String: String]?
    var pinnedEmoji: [String]?

    /// Enums store by raw value, so an unknown one is ignored rather than failing.
    struct SettingsData: Codable {
        // Adding a field here means adding it to SettingsBackupCoverage too, or the harness fails.
        // Carried, unlike the consent flags: recording your own copies grants no permission class.
        var clipboardEnabled: Bool?
        var clipboardRetentionDays: Int?
        var clipboardDefaultAction: String?
        var clipboardDisabledApps: [String]?
        var launchAtLogin: Bool?
        var hyperKey: String?
        var hyperKeyIncludesShift: Bool?
        var hyperKeyQuickPress: String?
        var hyperKeySecureInputCompatibility: Bool?
        var emojiSkinTone: String?
        var emojiGridColumns: Int?
        var showInMenuBar: Bool?
        var automaticallyCheckForUpdates: Bool?
        var popToRootSeconds: Int?
        var escapeKeyBehavior: String?
        var appearance: String?
        var language: String?
        var calcNumberStyle: String?
        var interfaceSize: String?
        var compactMode: Bool?
        var compactBarCommands: [String]?
        var searchScopes: [String]?
        var launcherShowsSuggestions: Bool?
        var rootSearchSensitivity: String?
        var openOnCursorScreen: Bool?
        // Safe to carry: it grants no permission class, just repositions the window.
        var paletteDraggable: Bool?
        var animationsEnabled: Bool?
        var fileSearchEnabled: Bool?
        var fileSearchScopes: [String]?
        var fileSearchIgnorePatterns: [String]?
        var fileSearchRemovedDefaultPatterns: [String]?
        var fileSearchShowInLauncher: Bool?
        var fileSearchIncludesHiddenFiles: Bool?
        var notesEnabled: Bool?
        var notesRendersMarkdown: Bool?
        var notesShowsFormattingBar: Bool?
        var notesShowsInMenuBar: Bool?
        // `snippetsEnabled` is absent: an import must not enable keystroke listening.
        var customCommandsEnabled: Bool?
        var customCommandsShowInLauncher: Bool?
        var snippetsShowInLauncher: Bool?
        var snippetDefaultAction: String?
        // Safe to carry: it grants no permission class paste doesn't already prompt for.
        var navigationEnabled: Bool?
        var menuSearchDisabledApps: [String]?
        var menuSearchShowsAppleMenu: Bool?
        var windowManagementEnabled: Bool?
        var windowManagementShowInLauncher: Bool?
        var windowGap: Int?
        var windowCycle: String?
        var windowWrapsDisplays: Bool?
        var windowKeepsProportions: Bool?
        var windowLayoutsShowInLauncher: Bool?
        var windowRoomsShowInLauncher: Bool?
        // Carried, unlike `snippetsEnabled`: opening a link grants no permission class of its own.
        var quicklinksEnabled: Bool?
        var quicklinksShowInLauncher: Bool?
        var extensionsShowInLauncher: Bool?
        var quicklinkOpensNewWindow: Bool?
        var quicklinkPassesSelectedText: Bool?
        var quicklinkConfirmsBeforeDelete: Bool?
        // Carried like quicklinks: running a shortcut the user built grants no permission class.
        var appleShortcutsEnabled: Bool?
        // `calendarEnabled` is absent: an import must not grant calendar access.
        var calendarShowInLauncher: Bool?
        var calendarLauncherLimit: Int?
        // Carried: it narrows what is read rather than widening what may be reached.
        var calendarSpan: Int?
        var joinWindowMinutes: Int?
        // `autoJoinMeetings` and `cameraPreview` are absent: an import must arm neither.
        var autoJoinConfirms: Bool?
        var autoJoinNamedProvidersOnly: Bool?
        var menuBarEvents: Int?
        var calendarMenuBarDisplay: Int?
        var menuBarLinkedEventsOnly: Bool?
        var calendarMenuBarHidesWhenEmpty: Bool?
        var hideCurrentEvent: Int?
        // Safe to carry: it silences a prompt rather than granting anything.
        var supportReminders: Bool?
    }

    struct HotkeyBackup: Codable {
        /// Named apart from `commands`: the launcher toggle is the one action with no command row.
        var togglePalette: HotKeyBinding?
        var commands: [String: HotKeyBinding]?
        var apps: [String: HotKeyBinding]?
        var panes: [String: HotKeyBinding]?
        var customCommands: [String: HotKeyBinding]?
        var systemActions: [String: HotKeyBinding]?
        var windowCommands: [String: HotKeyBinding]?
        var quicklinks: [String: HotKeyBinding]?
        var windowLayouts: [String: HotKeyBinding]?
        var windowRooms: [String: HotKeyBinding]?
        var customWindowSizes: [String: HotKeyBinding]?
    }

    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
        var aliases = 0
        var pinnedEmoji = 0
        var customCommands = 0
        var quicklinks = 0
        var windowLayouts = 0
        var windowRooms = 0
        var customWindowSizes = 0
    }
}

// MARK: - Slices

extension SettingsBackup {
    /// Settings & Shortcuts last: its favorites and aliases may name an item another slice brings.
    static let sliceCategories: [BackupCategory] = [
        .quicklinks, .customCommands, .windowManagement, .configuration
    ]

    /// Sliced again on read: a crafted file may carry another category's fields, such as commands.
    static func read(_ category: BackupCategory, from bundle: BackupBundle) -> SettingsBackup? {
        guard let data = try? Data(contentsOf: bundle.location(of: category)),
            let backup = try? SettingsBackup(json: data)
        else { return nil }
        return backup.slice(for: category)
    }

    func slice(for category: BackupCategory) -> SettingsBackup? {
        var part = SettingsBackup()
        switch category {
        case .configuration:
            part.settings = settings
            part.hotkeys = hotkeys
            part.hotkeys?.customCommands = nil
            part.hotkeys?.quicklinks = nil
            part.hotkeys?.windowLayouts = nil
            part.hotkeys?.windowRooms = nil
            part.hotkeys?.customWindowSizes = nil
            part.favoriteApps = favoriteApps
            part.hiddenLauncherItems = hiddenLauncherItems
            part.hiddenLauncherKinds = hiddenLauncherKinds
            part.launcherAliases = launcherAliases
            part.pinnedEmoji = pinnedEmoji
        case .quicklinks:
            part.quicklinks = quicklinks
            part.hotkeys = HotkeyBackup(quicklinks: hotkeys?.quicklinks)
        case .customCommands:
            part.customCommands = customCommands
            part.hotkeys = HotkeyBackup(customCommands: hotkeys?.customCommands)
        case .windowManagement:
            part.windowLayouts = windowLayouts
            part.windowRooms = windowRooms
            part.customWindowSizes = customWindowSizes
            part.hotkeys = HotkeyBackup(
                windowLayouts: hotkeys?.windowLayouts, windowRooms: hotkeys?.windowRooms,
                customWindowSizes: hotkeys?.customWindowSizes)
        case .clipboard, .snippets, .notes, .learning:
            return nil
        }
        return part
    }

    var contentCount: Int {
        [
            customCommands?.count, quicklinks?.count, windowLayouts?.count, windowRooms?.count,
            customWindowSizes?.count
        ].reduce(0) { $0 + ($1 ?? 0) }
    }
}

// MARK: - Serialization

extension SettingsBackup {
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    init(json: Data) throws {
        self = try JSONDecoder().decode(SettingsBackup.self, from: json)
    }
}
