import Foundation

@MainActor
extension SettingsBackup {
    static func gather(from core: AppCore) -> SettingsBackup {
        let s = core.settings
        var backup = SettingsBackup()
        backup.settings = SettingsData(
            clipboardEnabled: s.clipboardEnabled,
            clipboardRetentionDays: s.clipboardRetention.rawValue,
            clipboardDefaultAction: s.clipboardDefaultAction.rawValue,
            clipboardDisabledApps: s.clipboardDisabledApps,
            launchAtLogin: s.launchAtLogin,
            hyperKey: s.hyperKey.rawValue,
            hyperKeyIncludesShift: s.hyperKeyIncludesShift,
            hyperKeyQuickPress: s.hyperKeyQuickPress.rawValue,
            hyperKeySecureInputCompatibility: s.hyperKeySecureInputCompatibility,
            emojiSkinTone: s.emojiSkinTone.rawValue,
            emojiGridColumns: s.emojiGridColumns.rawValue,
            showInMenuBar: s.showInMenuBar,
            automaticallyCheckForUpdates: s.automaticallyCheckForUpdates,
            popToRootSeconds: s.popToRootTimeout.rawValue,
            escapeKeyBehavior: s.escapeKeyBehavior.rawValue,
            appearance: s.appearance.rawValue,
            language: s.language.rawValue,
            calcNumberStyle: s.calcNumberStyle.rawValue,
            interfaceSize: s.interfaceSize.rawValue,
            compactMode: s.compactMode,
            compactBarCommands: s.compactBarCommands.map(\.rawValue),
            searchScopes: s.searchScopes,
            launcherShowsSuggestions: s.launcherShowsSuggestions,
            rootSearchSensitivity: s.rootSearchSensitivity.rawValue,
            openOnCursorScreen: s.openOnCursorScreen,
            paletteDraggable: s.paletteDraggable,
            animationsEnabled: s.animationsEnabled,
            iconStyle: s.iconStyle.rawValue,
            fileSearchEnabled: s.fileSearchEnabled,
            fileSearchScopes: s.fileSearchScopes,
            fileSearchIgnorePatterns: s.fileSearchIgnorePatterns,
            fileSearchRemovedDefaultPatterns: s.fileSearchRemovedDefaultPatterns,
            fileSearchShowInLauncher: s.fileSearchShowInLauncher,
            fileSearchIncludesHiddenFiles: s.fileSearchIncludesHiddenFiles,
            notesEnabled: s.notesEnabled,
            notesRendersMarkdown: s.notesRendersMarkdown,
            notesShowsFormattingBar: s.notesShowsFormattingBar,
            notesShowsInMenuBar: s.notesShowsInMenuBar,
            customCommandsEnabled: s.customCommandsEnabled,
            customCommandsShowInLauncher: s.customCommandsShowInLauncher,
            snippetsShowInLauncher: s.snippetsShowInLauncher,
            snippetDefaultAction: s.snippetDefaultAction.rawValue,
            navigationEnabled: s.navigationEnabled,
            menuSearchDisabledApps: s.menuSearchDisabledApps,
            menuSearchShowsAppleMenu: s.menuSearchShowsAppleMenu,
            windowManagementEnabled: s.windowManagementEnabled,
            windowManagementShowInLauncher: s.windowManagementShowInLauncher,
            windowGap: s.windowGap,
            windowCycle: s.windowCycle.rawValue,
            windowWrapsDisplays: s.windowWrapsDisplays,
            windowKeepsProportions: s.windowKeepsProportions,
            windowLayoutsShowInLauncher: s.windowLayoutsShowInLauncher,
            windowRoomsShowInLauncher: s.windowRoomsShowInLauncher,
            quicklinksEnabled: s.quicklinksEnabled,
            quicklinksShowInLauncher: s.quicklinksShowInLauncher,
            extensionsShowInLauncher: s.extensionsShowInLauncher,
            quicklinkOpensNewWindow: s.quicklinkOpensNewWindow,
            quicklinkPassesSelectedText: s.quicklinkPassesSelectedText,
            quicklinkConfirmsBeforeDelete: s.quicklinkConfirmsBeforeDelete,
            appleShortcutsEnabled: s.appleShortcutsEnabled,
            calendarShowInLauncher: s.calendarShowInLauncher,
            calendarLauncherLimit: s.calendarLauncherLimit.rawValue,
            calendarSpan: s.calendarSpan.rawValue,
            joinWindowMinutes: s.joinWindowMinutes.rawValue,
            autoJoinConfirms: s.autoJoinConfirms,
            autoJoinNamedProvidersOnly: s.autoJoinNamedProvidersOnly,
            menuBarEvents: s.menuBarEvents.rawValue,
            calendarMenuBarDisplay: s.calendarMenuBarDisplay.rawValue,
            menuBarLinkedEventsOnly: s.menuBarLinkedEventsOnly,
            calendarMenuBarHidesWhenEmpty: s.calendarMenuBarHidesWhenEmpty,
            hideCurrentEvent: s.hideCurrentEvent.rawValue,
            supportReminders: s.supportRemindersEnabled)

        let hk = core.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.binding(for: .togglePalette)
        hotkeys.commands = Dictionary(
            uniqueKeysWithValues: CommandID.allCases.compactMap { id in
                id.hotKeyAction.flatMap(hk.binding(for:)).map { (id.rawValue, $0) }
            })
        hotkeys.apps = Dictionary(
            uniqueKeysWithValues: hk.boundBundleIDs.compactMap { id in
                hk.binding(for: .app(bundleID: id)).map { (id, $0) }
            })
        hotkeys.panes = Dictionary(
            uniqueKeysWithValues: hk.boundPaneBundleIDs.compactMap { id in
                hk.binding(for: .settingsPane(bundleID: id)).map { (id, $0) }
            })
        hotkeys.customCommands = Dictionary(
            uniqueKeysWithValues: hk.boundCustomCommandIDs.compactMap { id in
                hk.binding(for: .customCommand(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.systemActions = Dictionary(
            uniqueKeysWithValues: SystemAction.ID.allCases.compactMap { id in
                hk.binding(for: .systemAction(id: id)).map { (id.rawValue, $0) }
            })
        hotkeys.windowCommands = Dictionary(
            uniqueKeysWithValues: WindowCommand.ID.allCases.compactMap { id in
                hk.binding(for: .windowCommand(id: id)).map { (id.rawValue, $0) }
            })
        hotkeys.quicklinks = Dictionary(
            uniqueKeysWithValues: hk.boundQuicklinkIDs.compactMap { id in
                hk.binding(for: .quicklink(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.windowLayouts = Dictionary(
            uniqueKeysWithValues: hk.boundWindowLayoutIDs.compactMap { id in
                hk.binding(for: .windowLayout(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.windowRooms = Dictionary(
            uniqueKeysWithValues: hk.boundWindowRoomIDs.compactMap { id in
                hk.binding(for: .windowRoom(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.customWindowSizes = Dictionary(
            uniqueKeysWithValues: hk.boundCustomWindowSizeIDs.compactMap { id in
                hk.binding(for: .customWindowSize(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        backup.hotkeys = hotkeys

        backup.customCommands = core.customCommands.commands
        backup.quicklinks = core.quicklinks.quicklinks
        backup.windowLayouts = core.windowLayouts.layouts
        backup.windowRooms = core.rooms.rooms
        backup.customWindowSizes = core.customWindowSizes.sizes
        backup.favoriteApps = core.favorites.keys
        backup.hiddenLauncherItems = Array(core.visibility.hiddenItemKeys)
        backup.hiddenLauncherKinds = Array(core.visibility.disabledKinds)
        backup.launcherAliases = core.aliases.aliases
        backup.pinnedEmoji = core.pinnedEmoji.glyphs
        return backup
    }

    func apply(to core: AppCore, into summary: inout ApplySummary) {
        if let s = settings { summary.settingsFields += applySettings(s, to: core) }
        if let customCommands {
            summary.customCommands += core.customCommandCoordinator.replaceCustomCommands(customCommands)
        }
        // Before the hotkeys, so a restored binding has its quicklink to attach to.
        if let quicklinks {
            summary.quicklinks += core.quicklinkCoordinator.replaceQuicklinks(quicklinks)
        }
        // Before the hotkeys too, for the same reason: a binding needs its layout to attach to.
        if let windowLayouts {
            summary.windowLayouts +=
                core.windowLayoutCoordinator.replaceWindowLayouts(windowLayouts)
        }
        if let windowRooms {
            summary.windowRooms += core.roomCoordinator.replaceRooms(windowRooms)
        }
        if let customWindowSizes {
            summary.customWindowSizes +=
                core.customWindowSizeCoordinator.replaceCustomWindowSizes(customWindowSizes)
        }
        if let hotkeys { summary.hotkeys += applyHotkeys(hotkeys, to: core) }
        if let favoriteApps {
            core.favorites.replace(keys: favoriteApps)
            summary.favorites += favoriteApps.count
        }
        if hiddenLauncherItems != nil || hiddenLauncherKinds != nil {
            let items = hiddenLauncherItems ?? Array(core.visibility.hiddenItemKeys)
            let kinds = hiddenLauncherKinds ?? Array(core.visibility.disabledKinds)
            core.visibility.replace(hiddenItems: items, disabledKinds: kinds)
            summary.hiddenItems += items.count
        }
        if let launcherAliases {
            core.aliases.replace(launcherAliases)
            // Counted after the store, which drops blanks the file may carry.
            summary.aliases += core.aliases.aliases.count
        }
        if let pinnedEmoji {
            core.pinnedEmoji.replace(pinnedEmoji)
            summary.pinnedEmoji += core.pinnedEmoji.glyphs.count
        }
    }

    private func applySettings(_ s: SettingsData, to core: AppCore) -> Int {
        let settings = core.settings
        var count = 0
        if let flag = s.clipboardEnabled {
            settings.clipboardEnabled = flag
            count += 1
        }
        if let days = s.clipboardRetentionDays, let retention = ClipboardRetention(rawValue: days) {
            settings.clipboardRetention = retention
            count += 1
        }
        if let apps = s.clipboardDisabledApps {
            settings.clipboardDisabledApps = apps
            count += 1
        }
        if let raw = s.clipboardDefaultAction, let action = ClipboardDefaultAction(rawValue: raw) {
            settings.clipboardDefaultAction = action
            count += 1
        }
        if let launch = s.launchAtLogin {
            settings.launchAtLogin = launch
            count += 1
        }
        if let raw = s.hyperKey, let key = HyperKeyPhysicalKey(rawValue: raw) {
            settings.hyperKey = key
            count += 1
        }
        if let flag = s.hyperKeyIncludesShift {
            settings.hyperKeyIncludesShift = flag
            count += 1
        }
        if let raw = s.hyperKeyQuickPress, let quick = HyperKeyQuickPress(rawValue: raw) {
            settings.hyperKeyQuickPress = quick
            count += 1
        }
        if let flag = s.hyperKeySecureInputCompatibility {
            settings.hyperKeySecureInputCompatibility = flag
            count += 1
        }
        if let raw = s.emojiSkinTone, let tone = EmojiSkinTone(rawValue: raw) {
            settings.emojiSkinTone = tone
            count += 1
        }
        if let raw = s.emojiGridColumns, let columns = EmojiGridColumns(rawValue: raw) {
            settings.emojiGridColumns = columns
            count += 1
        }
        if let show = s.showInMenuBar {
            settings.showInMenuBar = show
            count += 1
        }
        if let automaticallyCheck = s.automaticallyCheckForUpdates {
            settings.automaticallyCheckForUpdates = automaticallyCheck
            count += 1
        }
        if let secs = s.popToRootSeconds, let timeout = PopToRootTimeout(rawValue: secs) {
            settings.popToRootTimeout = timeout
            count += 1
        }
        if let raw = s.escapeKeyBehavior, let behavior = EscapeKeyBehavior(rawValue: raw) {
            settings.escapeKeyBehavior = behavior
            count += 1
        }
        if let raw = s.interfaceSize, let size = InterfaceSize(rawValue: raw) {
            settings.interfaceSize = size
            count += 1
        }
        if let raw = s.appearance, let appearance = AppAppearance(rawValue: raw) {
            settings.appearance = appearance
            count += 1
        }
        if let raw = s.language, let language = AppLanguage(rawValue: raw) {
            settings.language = language
            count += 1
        }
        if let raw = s.calcNumberStyle, let style = CalcNumberStyle(rawValue: raw) {
            settings.calcNumberStyle = style
            count += 1
        }
        if let flag = s.compactMode {
            settings.compactMode = flag
            count += 1
        }
        if let identifiers = s.compactBarCommands,
            let commands = CommandID.compactBarCommands(from: identifiers)
        {
            settings.compactBarCommands = commands
            count += 1
        }
        if let scopes = s.searchScopes {
            settings.searchScopes = SearchScopes.normalize(scopes)
            count += 1
        }
        if let flag = s.launcherShowsSuggestions {
            settings.launcherShowsSuggestions = flag
            count += 1
        }
        if let raw = s.rootSearchSensitivity, let sensitivity = SearchSensitivity(rawValue: raw) {
            settings.rootSearchSensitivity = sensitivity
            count += 1
        }
        if let flag = s.openOnCursorScreen {
            settings.openOnCursorScreen = flag
            count += 1
        }
        if let flag = s.paletteDraggable {
            settings.paletteDraggable = flag
            count += 1
        }
        if let flag = s.animationsEnabled {
            settings.animationsEnabled = flag
            count += 1
        }
        if let raw = s.iconStyle, let style = IconStyle(rawValue: raw) {
            settings.iconStyle = style
            count += 1
        }
        // Writing through AppSettings is enough; AppCore's sinks re-project the rest.
        if let flag = s.fileSearchEnabled {
            settings.fileSearchEnabled = flag
            count += 1
        }
        if let scopes = s.fileSearchScopes {
            settings.fileSearchScopes = scopes
            count += 1
        }
        if let patterns = s.fileSearchIgnorePatterns {
            settings.fileSearchIgnorePatterns = patterns
            count += 1
        }
        if let patterns = s.fileSearchRemovedDefaultPatterns {
            settings.fileSearchRemovedDefaultPatterns = patterns
            count += 1
        }
        if let flag = s.fileSearchShowInLauncher {
            settings.fileSearchShowInLauncher = flag
            count += 1
        }
        if let flag = s.fileSearchIncludesHiddenFiles {
            settings.fileSearchIncludesHiddenFiles = flag
            count += 1
        }
        if let flag = s.notesEnabled {
            settings.notesEnabled = flag
            count += 1
        }
        if let flag = s.notesRendersMarkdown {
            settings.notesRendersMarkdown = flag
            count += 1
        }
        if let flag = s.notesShowsFormattingBar {
            settings.notesShowsFormattingBar = flag
            count += 1
        }
        if let flag = s.notesShowsInMenuBar {
            settings.notesShowsInMenuBar = flag
            count += 1
        }
        if let flag = s.customCommandsEnabled {
            settings.customCommandsEnabled = flag
            count += 1
        }
        if let flag = s.customCommandsShowInLauncher {
            settings.customCommandsShowInLauncher = flag
            count += 1
        }
        if let flag = s.snippetsShowInLauncher {
            settings.snippetsShowInLauncher = flag
            count += 1
        }
        if let raw = s.snippetDefaultAction, let action = SnippetDefaultAction(rawValue: raw) {
            settings.snippetDefaultAction = action
            count += 1
        }
        if let flag = s.navigationEnabled {
            settings.navigationEnabled = flag
            count += 1
        }
        if let apps = s.menuSearchDisabledApps {
            settings.menuSearchDisabledApps = apps
            count += 1
        }
        if let flag = s.menuSearchShowsAppleMenu {
            settings.menuSearchShowsAppleMenu = flag
            count += 1
        }
        if let flag = s.windowManagementEnabled {
            settings.windowManagementEnabled = flag
            count += 1
        }
        if let flag = s.windowManagementShowInLauncher {
            settings.windowManagementShowInLauncher = flag
            count += 1
        }
        if let gap = s.windowGap {
            settings.windowGap = gap
            count += 1
        }
        if let raw = s.windowCycle, let cycle = WindowCycle(rawValue: raw) {
            settings.windowCycle = cycle
            count += 1
        }
        if let flag = s.windowWrapsDisplays {
            settings.windowWrapsDisplays = flag
            count += 1
        }
        if let flag = s.windowKeepsProportions {
            settings.windowKeepsProportions = flag
            count += 1
        }
        if let flag = s.windowLayoutsShowInLauncher {
            settings.windowLayoutsShowInLauncher = flag
            count += 1
        }
        if let flag = s.windowRoomsShowInLauncher {
            settings.windowRoomsShowInLauncher = flag
            count += 1
        }
        if let flag = s.quicklinksEnabled {
            settings.quicklinksEnabled = flag
            count += 1
        }
        if let flag = s.extensionsShowInLauncher {
            settings.extensionsShowInLauncher = flag
            count += 1
        }
        if let flag = s.quicklinksShowInLauncher {
            settings.quicklinksShowInLauncher = flag
            count += 1
        }
        if let flag = s.appleShortcutsEnabled {
            settings.appleShortcutsEnabled = flag
            count += 1
        }
        if let flag = s.quicklinkOpensNewWindow {
            settings.quicklinkOpensNewWindow = flag
            count += 1
        }
        if let flag = s.quicklinkPassesSelectedText {
            settings.quicklinkPassesSelectedText = flag
            count += 1
        }
        if let flag = s.quicklinkConfirmsBeforeDelete {
            settings.quicklinkConfirmsBeforeDelete = flag
            count += 1
        }
        if let flag = s.calendarShowInLauncher {
            settings.calendarShowInLauncher = flag
            count += 1
        }
        if let raw = s.calendarLauncherLimit, let limit = CalendarLauncherLimit(rawValue: raw) {
            settings.calendarLauncherLimit = limit
            count += 1
        }
        if let raw = s.calendarSpan, let span = MeetingSpan(rawValue: raw) {
            settings.calendarSpan = span
            count += 1
        }
        if let raw = s.joinWindowMinutes, let window = JoinWindow(rawValue: raw) {
            settings.joinWindowMinutes = window
            count += 1
        }
        if let flag = s.autoJoinConfirms {
            settings.autoJoinConfirms = flag
            count += 1
        }
        if let flag = s.autoJoinNamedProvidersOnly {
            settings.autoJoinNamedProvidersOnly = flag
            count += 1
        }
        if let raw = s.menuBarEvents, let lead = MenuBarEvents(rawValue: raw) {
            settings.menuBarEvents = lead
            count += 1
        }
        if let raw = s.calendarMenuBarDisplay,
            let display = CalendarMenuBarDisplay(rawValue: raw)
        {
            settings.calendarMenuBarDisplay = display
            count += 1
        }
        if let flag = s.menuBarLinkedEventsOnly {
            settings.menuBarLinkedEventsOnly = flag
            count += 1
        }
        if let flag = s.calendarMenuBarHidesWhenEmpty {
            settings.calendarMenuBarHidesWhenEmpty = flag
            count += 1
        }
        if let raw = s.hideCurrentEvent, let hide = HideCurrentEvent(rawValue: raw) {
            settings.hideCurrentEvent = hide
            count += 1
        }
        if let flag = s.supportReminders {
            settings.supportRemindersEnabled = flag
            count += 1
        }
        return count
    }

    private func applyHotkeys(_ hotkeys: HotkeyBackup, to core: AppCore) -> Int {
        let hk = core.hotKeys
        var count = 0
        // Skip an already-claimed binding: the second registration would silently fail.
        func apply(_ binding: HotKeyBinding, _ action: HotKeyAction) {
            guard hk.conflictOwner(of: binding, excluding: action) == nil else { return }
            hk.setBinding(binding, for: action)
            count += 1
        }
        if let b = hotkeys.togglePalette { apply(b, .togglePalette) }
        for (rawID, b) in hotkeys.commands ?? [:] {
            guard let action = CommandID(rawValue: rawID)?.hotKeyAction else { continue }
            apply(b, action)
        }
        for (id, b) in hotkeys.apps ?? [:] { apply(b, .app(bundleID: id)) }
        for (id, b) in hotkeys.panes ?? [:] { apply(b, .settingsPane(bundleID: id)) }
        for (rawID, b) in hotkeys.customCommands ?? [:] {
            guard let id = UUID(uuidString: rawID), core.customCommands.command(id: id) != nil else {
                continue
            }
            apply(b, .customCommand(id: id))
        }
        for (rawID, b) in hotkeys.systemActions ?? [:] {
            guard let id = SystemAction.ID(rawValue: rawID) else { continue }
            apply(b, .systemAction(id: id))
        }
        for (rawID, b) in hotkeys.windowCommands ?? [:] {
            guard let id = WindowCommand.ID(rawValue: rawID) else { continue }
            apply(b, .windowCommand(id: id))
        }
        for (rawID, b) in hotkeys.windowLayouts ?? [:] {
            guard let id = UUID(uuidString: rawID), core.windowLayouts.layout(id: id) != nil
            else { continue }
            apply(b, .windowLayout(id: id))
        }
        for (rawID, b) in hotkeys.windowRooms ?? [:] {
            guard let id = UUID(uuidString: rawID), core.rooms.room(id: id) != nil else { continue }
            apply(b, .windowRoom(id: id))
        }
        for (rawID, b) in hotkeys.customWindowSizes ?? [:] {
            guard let id = UUID(uuidString: rawID), core.customWindowSizes.size(id: id) != nil
            else { continue }
            apply(b, .customWindowSize(id: id))
        }
        for (rawID, b) in hotkeys.quicklinks ?? [:] {
            guard let id = UUID(uuidString: rawID), core.quicklinks.quicklink(id: id) != nil else {
                continue
            }
            apply(b, .quicklink(id: id))
        }
        return count
    }
}
