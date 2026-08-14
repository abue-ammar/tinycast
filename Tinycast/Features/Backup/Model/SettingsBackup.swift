import Foundation

/// A readable configuration snapshot; every field is optional, so an import merges.
struct SettingsBackup: Codable {
    var version = 4
    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    var quicklinks: [Quicklink]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?

    /// Enums store by raw value, so an unknown one is ignored rather than failing.
    struct SettingsData: Codable {
        // Adding a field here means adding it to SettingsBackupCoverage too, or the harness fails.
        var clipboardRetentionDays: Int?
        var clipboardDisabledApps: [String]?
        var launchAtLogin: Bool?
        var hyperKey: String?
        var hyperKeyIncludesShift: Bool?
        var hyperKeyQuickPress: String?
        var emojiSkinTone: String?
        var showInMenuBar: Bool?
        var popToRootSeconds: Int?
        var compactMode: Bool?
        var showFavoritesInCompactMode: Bool?
        var searchScopes: [String]?
        var openOnCursorScreen: Bool?
        // Safe to carry: it grants no permission class, just repositions the window.
        var paletteDraggable: Bool?
        var fileSearchEnabled: Bool?
        var fileSearchScopes: [String]?
        var fileSearchIgnorePatterns: [String]?
        // `snippetsEnabled` is absent: an import must not enable keystroke listening.
        var customCommandsEnabled: Bool?
        var customCommandsShowInLauncher: Bool?
        var snippetsShowInLauncher: Bool?
        // Safe to carry: it grants no permission class paste doesn't already prompt for.
        var windowManagementEnabled: Bool?
        var windowManagementShowInLauncher: Bool?
        var windowGap: Int?
        var windowCycleOnRepeat: Bool?
        // Carried, unlike `snippetsEnabled`: opening a link grants no permission class of its own.
        var quicklinksEnabled: Bool?
        var quicklinksShowInLauncher: Bool?
        var extensionsShowInLauncher: Bool?
        var quicklinkOpensNewWindow: Bool?
        var quicklinkSelectionFallback: String?
        var quicklinkConfirmsBeforeDelete: Bool?
    }

    /// Combos keep the legacy shape, so older files import. docs/features/hotkeys.md#persistence
    struct HotkeyBackup: Codable {
        var togglePalette: HotKeyBinding?
        var toggleClipboard: HotKeyBinding?
        var toggleEmoji: HotKeyBinding?
        var searchFiles: HotKeyBinding?
        var apps: [String: HotKeyBinding]?
        var panes: [String: HotKeyBinding]?
        var customCommands: [String: HotKeyBinding]?
        var systemActions: [String: HotKeyBinding]?
        var windowCommands: [String: HotKeyBinding]?
        var quicklinks: [String: HotKeyBinding]?
    }

    /// A tally of what an import touched, for user-facing confirmation.
    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
        var customCommands = 0
        var quicklinks = 0
    }
}

// MARK: - Gather / apply (main-actor: reads and writes the live stores)

@MainActor
extension SettingsBackup {
    static func gather(from core: AppCore) -> SettingsBackup {
        let s = core.settings
        var backup = SettingsBackup()
        backup.settings = SettingsData(
            clipboardRetentionDays: s.clipboardRetention.rawValue,
            clipboardDisabledApps: s.clipboardDisabledApps,
            launchAtLogin: s.launchAtLogin,
            hyperKey: s.hyperKey.rawValue,
            hyperKeyIncludesShift: s.hyperKeyIncludesShift,
            hyperKeyQuickPress: s.hyperKeyQuickPress.rawValue,
            emojiSkinTone: s.emojiSkinTone.rawValue,
            showInMenuBar: UserDefaults.standard.object(forKey: SettingsKey.showInMenuBar) as? Bool
                ?? true,
            popToRootSeconds: s.popToRootTimeout.rawValue,
            compactMode: s.compactMode,
            showFavoritesInCompactMode: s.showFavoritesInCompactMode,
            searchScopes: s.searchScopes,
            openOnCursorScreen: s.openOnCursorScreen,
            paletteDraggable: s.paletteDraggable,
            fileSearchEnabled: s.fileSearchEnabled,
            fileSearchScopes: s.fileSearchScopes,
            fileSearchIgnorePatterns: s.fileSearchIgnorePatterns,
            customCommandsEnabled: s.customCommandsEnabled,
            customCommandsShowInLauncher: s.customCommandsShowInLauncher,
            snippetsShowInLauncher: s.snippetsShowInLauncher,
            windowManagementEnabled: s.windowManagementEnabled,
            windowManagementShowInLauncher: s.windowManagementShowInLauncher,
            windowGap: s.windowGap,
            windowCycleOnRepeat: s.windowCycleOnRepeat,
            quicklinksEnabled: s.quicklinksEnabled,
            quicklinksShowInLauncher: s.quicklinksShowInLauncher,
            extensionsShowInLauncher: s.extensionsShowInLauncher,
            quicklinkOpensNewWindow: s.quicklinkOpensNewWindow,
            quicklinkSelectionFallback: s.quicklinkSelectionFallback.rawValue,
            quicklinkConfirmsBeforeDelete: s.quicklinkConfirmsBeforeDelete)

        let hk = core.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.binding(for: .togglePalette)
        hotkeys.toggleClipboard = hk.binding(for: .toggleClipboard)
        hotkeys.toggleEmoji = hk.binding(for: .toggleEmoji)
        hotkeys.searchFiles = hk.binding(for: .searchFiles)
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
        backup.hotkeys = hotkeys

        backup.customCommands = core.customCommands.commands
        backup.quicklinks = core.quicklinks.quicklinks
        backup.favoriteApps = core.favorites.keys
        backup.hiddenLauncherItems = Array(core.visibility.hiddenItemKeys)
        backup.hiddenLauncherKinds = Array(core.visibility.hiddenKinds)
        return backup
    }

    @discardableResult
    func apply(to core: AppCore) -> ApplySummary {
        var summary = ApplySummary()
        if let s = settings { summary.settingsFields = applySettings(s, to: core) }
        if let customCommands {
            summary.customCommands = core.customCommandCoordinator.replaceCustomCommands(customCommands)
        }
        // Before the hotkeys, so a restored binding has its quicklink to attach to.
        if let quicklinks {
            summary.quicklinks = core.quicklinkCoordinator.replaceQuicklinks(quicklinks)
        }
        if let hotkeys { summary.hotkeys = applyHotkeys(hotkeys, to: core) }
        if let favoriteApps {
            core.favorites.replace(keys: favoriteApps)
            summary.favorites = favoriteApps.count
        }
        if hiddenLauncherItems != nil || hiddenLauncherKinds != nil {
            let items = hiddenLauncherItems ?? Array(core.visibility.hiddenItemKeys)
            let kinds = hiddenLauncherKinds ?? Array(core.visibility.hiddenKinds)
            core.visibility.replace(hiddenItems: items, hiddenKinds: kinds)
            summary.hiddenItems = items.count
        }
        return summary
    }

    private func applySettings(_ s: SettingsData, to core: AppCore) -> Int {
        let settings = core.settings
        var count = 0
        if let days = s.clipboardRetentionDays, let retention = ClipboardRetention(rawValue: days) {
            settings.clipboardRetention = retention
            core.clipboardCoordinator.applyRetention(retention)
            count += 1
        }
        if let apps = s.clipboardDisabledApps {
            settings.clipboardDisabledApps = apps
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
        if let raw = s.emojiSkinTone, let tone = EmojiSkinTone(rawValue: raw) {
            settings.emojiSkinTone = tone
            count += 1
        }
        if let show = s.showInMenuBar {
            UserDefaults.standard.set(show, forKey: SettingsKey.showInMenuBar)
            count += 1
        }
        if let secs = s.popToRootSeconds, let timeout = PopToRootTimeout(rawValue: secs) {
            settings.popToRootTimeout = timeout
            count += 1
        }
        if let flag = s.compactMode {
            settings.compactMode = flag
            count += 1
        }
        if let flag = s.showFavoritesInCompactMode {
            settings.showFavoritesInCompactMode = flag
            count += 1
        }
        if let scopes = s.searchScopes {
            settings.searchScopes = SearchScopes.normalize(scopes)
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
        if let flag = s.windowCycleOnRepeat {
            settings.windowCycleOnRepeat = flag
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
        if let flag = s.quicklinkOpensNewWindow {
            settings.quicklinkOpensNewWindow = flag
            count += 1
        }
        if let raw = s.quicklinkSelectionFallback,
            let fallback = QuicklinkSelectionFallback(rawValue: raw)
        {
            settings.quicklinkSelectionFallback = fallback
            count += 1
        }
        if let flag = s.quicklinkConfirmsBeforeDelete {
            settings.quicklinkConfirmsBeforeDelete = flag
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
        if let b = hotkeys.toggleClipboard { apply(b, .toggleClipboard) }
        if let b = hotkeys.toggleEmoji { apply(b, .toggleEmoji) }
        if let b = hotkeys.searchFiles { apply(b, .searchFiles) }
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
        for (rawID, b) in hotkeys.quicklinks ?? [:] {
            guard let id = UUID(uuidString: rawID), core.quicklinks.quicklink(id: id) != nil else {
                continue
            }
            apply(b, .quicklink(id: id))
        }
        return count
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
