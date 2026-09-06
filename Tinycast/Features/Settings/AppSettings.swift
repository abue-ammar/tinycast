import SwiftUI

/// Keys shared between `@AppStorage` sites, so app and Settings bind to the same one.
enum SettingsKey {
    /// The launcher icon's visibility — read by its `MenuBarExtra` and the General toggle.
    static let showInMenuBar = "showInMenuBar"
    static let calendarMenuBarDisplay = "calendarMenuBarDisplay"
}

/// Delay before a closed palette pops to root; an unset key reads as `.immediately`.
enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately ? "Immediately" : "After \(rawValue) seconds"
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

/// How early the join card appears, and how long past the start it stays. See UpcomingWindow.
enum JoinWindow: Int, CaseIterable, Identifiable, Sendable {
    case one = 1
    case two = 2
    case five = 5
    case ten = 10
    case fifteen = 15

    var id: Int { rawValue }

    var title: String { rawValue == 1 ? "1 minute" : "\(rawValue) minutes" }
}

/// How early the calendar item picks the next event up. Zero, which `integer(forKey:)` also
/// returns unset, keeps it for the rest of today.
enum MenuBarEvents: Int, CaseIterable, Identifiable, Sendable {
    case today = 0
    case two = 2
    case five = 5
    case ten = 10
    case thirty = 30

    var id: Int { rawValue }

    var title: String { self == .today ? "Today" : "\(rawValue) minutes before" }
}

/// The calendar's independent menu-bar presence. Zero matches an unset preference.
enum CalendarMenuBarDisplay: Int, CaseIterable, Identifiable, Sendable {
    case disabled = 0
    case meetingIcon = 1
    case meetingTitle = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .meetingIcon: "Meeting Icon"
        case .meetingTitle: "Meeting Title"
        }
    }
}

/// How long a started event holds the menu bar. Zero, the default, means it goes as it starts.
enum CalendarLauncherLimit: Int, CaseIterable, Identifiable, Sendable {
    case one = 1
    case three = 3
    case five = 5
    case all = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .one: "1 next"
        case .three: "3 next"
        case .five: "5 next"
        case .all: "All"
        }
    }

    var maximum: Int? { self == .all ? nil : rawValue }
}

/// Whether a started event remains in the menu bar long enough to show its time left.
enum HideCurrentEvent: Int, CaseIterable, Identifiable, Sendable {
    case dontHide = -1
    case automatically = 0
    case afterFive = 5
    case afterTen = 10
    case afterThirty = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dontHide: "Keep visible — show time left"
        case .automatically: "Automatically"
        default: "After \(rawValue) minutes"
        }
    }

    var hidesAtStart: Bool { self == .automatically }
    var minutes: Int? { rawValue > 0 ? rawValue : nil }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    private typealias Key = AppSettingsKey

    /// What `AppIndex` scans, in scan order; editing it re-indexes, being observed.
    var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes.rawValue) }
    }

    /// Ships on, unlike every other feature switch: a launcher is expected to keep history.
    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled.rawValue) }
    }

    var clipboardRetention: ClipboardRetention {
        didSet {
            defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention.rawValue)
        }
    }

    /// Bundle IDs never recorded from; ordered, so the Settings list stays stable.
    var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps.rawValue) }
    }

    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    /// The physical key remapped to the Hyper chord; `HyperKeyTap` reacts via its observer.
    var hyperKey: HyperKeyPhysicalKey {
        didSet { defaults.set(hyperKey.rawValue, forKey: Key.hyperKey.rawValue) }
    }

    /// Whether Hyper is ⌃⌥⇧⌘ (on) or ⌃⌥⌘ (off).
    var hyperKeyIncludesShift: Bool {
        didSet { defaults.set(hyperKeyIncludesShift, forKey: Key.hyperKeyIncludesShift.rawValue) }
    }

    var hyperKeyQuickPress: HyperKeyQuickPress {
        didSet {
            defaults.set(hyperKeyQuickPress.rawValue, forKey: Key.hyperKeyQuickPress.rawValue)
        }
    }

    /// Preferred skin tone applied to modifier-capable emoji at render and copy time.
    var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone.rawValue) }
    }

    /// How long a closed palette keeps its state before popping back to the root launcher.
    var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout.rawValue) }
    }

    /// Follow macOS, or pin Tinycast to one appearance. Applied by `AppCore.applyAppearance()`.
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance.rawValue) }
    }

    /// Summon the launcher as a slim search bar that expands into the full list on typing.
    var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode.rawValue) }
    }

    /// Pin favorite app icons to the right of the compact search bar (⌘1–⌘5 to launch).
    var showFavoritesInCompactMode: Bool {
        didSet {
            defaults.set(
                showFavoritesInCompactMode, forKey: Key.showFavoritesInCompactMode.rawValue)
        }
    }

    /// Summon the palette on the display under the pointer instead of the one holding the menu bar.
    var openOnCursorScreen: Bool {
        didSet { defaults.set(openOnCursorScreen, forKey: Key.openOnCursorScreen.rawValue) }
    }

    var autoSwitchInputSourceID: String? {
        didSet {
            guard let autoSwitchInputSourceID else {
                defaults.removeObject(forKey: Key.autoSwitchInputSource.rawValue)
                return
            }
            defaults.set(autoSwitchInputSourceID, forKey: Key.autoSwitchInputSource.rawValue)
        }
    }

    /// Lets the panel be dragged by its top edge; off by default, so most launches never grab it.
    var paletteDraggable: Bool {
        didSet { defaults.set(paletteDraggable, forKey: Key.paletteDraggable.rawValue) }
    }

    /// Where a drag left the panel's top-left; nil means the default placement.
    var palettePosition: CGPoint? {
        didSet {
            guard let palettePosition else {
                defaults.removeObject(forKey: Key.palettePosition.rawValue)
                return
            }
            defaults.set(
                [palettePosition.x, palettePosition.y], forKey: Key.palettePosition.rawValue)
        }
    }

    // Feature switches, off out of the box, and off means fully off.
    var fileSearchEnabled: Bool {
        didSet { defaults.set(fileSearchEnabled, forKey: Key.fileSearchEnabled.rawValue) }
    }

    /// Tilde-abbreviated, so a backup taken on one machine still points somewhere on another.
    var fileSearchScopes: [String] {
        didSet { defaults.set(fileSearchScopes, forKey: Key.fileSearchScopes.rawValue) }
    }

    /// Only what the user added; the shipped rules are compiled into `FileSearchIgnoreList`.
    var fileSearchIgnorePatterns: [String] {
        didSet {
            defaults.set(fileSearchIgnorePatterns, forKey: Key.fileSearchIgnorePatterns.rawValue)
        }
    }

    var notesEnabled: Bool {
        didSet { defaults.set(notesEnabled, forKey: Key.notesEnabled.rawValue) }
    }

    /// Off by default: connecting a server is consent to run code Tinycast did not write.
    var mcpEnabled: Bool {
        didSet { defaults.set(mcpEnabled, forKey: Key.mcpEnabled.rawValue) }
    }
    var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Key.aiEnabled.rawValue) }
    }

    var customCommandsEnabled: Bool {
        didSet { defaults.set(customCommandsEnabled, forKey: Key.customCommandsEnabled.rawValue) }
    }

    /// With the feature on, controls only whether its launcher section appears.
    var customCommandsShowInLauncher: Bool {
        didSet {
            defaults.set(
                customCommandsShowInLauncher, forKey: Key.customCommandsShowInLauncher.rawValue)
        }
    }

    /// Also keyword-expansion consent, so it confirms first and never rides a backup.
    var snippetsEnabled: Bool {
        didSet { defaults.set(snippetsEnabled, forKey: Key.snippetsEnabled.rawValue) }
    }

    /// Off out of the box: on means Tinycast may read a selection anywhere and type over it.
    var quickActionsEnabled: Bool {
        didSet { defaults.set(quickActionsEnabled, forKey: Key.quickActionsEnabled.rawValue) }
    }

    var snippetsShowInLauncher: Bool {
        didSet { defaults.set(snippetsShowInLauncher, forKey: Key.snippetsShowInLauncher.rawValue) }
    }

    /// Consent to run third-party JavaScript: it confirms, defaults off, rides no backup.
    var extensionsEnabled: Bool {
        didSet { defaults.set(extensionsEnabled, forKey: Key.extensionsEnabled.rawValue) }
    }

    var extensionsShowInLauncher: Bool {
        didSet {
            defaults.set(extensionsShowInLauncher, forKey: Key.extensionsShowInLauncher.rawValue)
        }
    }

    /// Only a source registry needs one — the store serves extensions already built.
    var extensionPackageManager: ExtensionPackageManager {
        didSet {
            defaults.set(
                extensionPackageManager.rawValue, forKey: Key.extensionPackageManager.rawValue)
        }
    }

    /// Seeded with the store and the official repository; a user can add their own.
    var extensionRegistries: [ExtensionRegistry] {
        didSet {
            guard let data = try? JSONEncoder().encode(extensionRegistries) else { return }
            defaults.set(data, forKey: Key.extensionRegistries.rawValue)
        }
    }

    /// For a toolchain Tinycast doesn't know — mise or Nix shims are the common case.
    var extensionCustomSearchPaths: [String] {
        didSet {
            defaults.set(
                extensionCustomSearchPaths, forKey: Key.extensionCustomSearchPaths.rawValue)
        }
    }

    /// Doubles as calendar-access consent, so only `CalendarCoordinator` may write it.
    var calendarEnabled: Bool {
        didSet { defaults.set(calendarEnabled, forKey: Key.calendarEnabled.rawValue) }
    }

    var calendarShowInLauncher: Bool {
        didSet {
            defaults.set(calendarShowInLauncher, forKey: Key.calendarShowInLauncher.rawValue)
        }
    }

    var calendarLauncherLimit: CalendarLauncherLimit {
        didSet {
            defaults.set(calendarLauncherLimit.rawValue, forKey: Key.calendarLauncherLimit.rawValue)
        }
    }

    /// Narrows the fetch itself rather than what is shown, so every surface reads the same days.
    var calendarIncludesTomorrow: Bool {
        didSet {
            defaults.set(calendarIncludesTomorrow, forKey: Key.calendarIncludesTomorrow.rawValue)
        }
    }

    var joinWindowMinutes: JoinWindow {
        didSet { defaults.set(joinWindowMinutes.rawValue, forKey: Key.joinWindowMinutes.rawValue) }
    }

    /// Arms the app to open meeting links unattended, so only the Calendar pane's switch writes it.
    var autoJoinMeetings: Bool {
        didSet { defaults.set(autoJoinMeetings, forKey: Key.autoJoinMeetings.rawValue) }
    }

    var autoJoinConfirms: Bool {
        didSet { defaults.set(autoJoinConfirms, forKey: Key.autoJoinConfirms.rawValue) }
    }

    /// Doubles as camera consent, so only the Calendar pane's switch writes it.
    var cameraPreview: Bool {
        didSet { defaults.set(cameraPreview, forKey: Key.cameraPreview.rawValue) }
    }

    var menuBarEvents: MenuBarEvents {
        didSet { defaults.set(menuBarEvents.rawValue, forKey: Key.menuBarEvents.rawValue) }
    }

    var calendarMenuBarDisplay: CalendarMenuBarDisplay {
        didSet {
            defaults.set(
                calendarMenuBarDisplay.rawValue, forKey: Key.calendarMenuBarDisplay.rawValue)
        }
    }

    var menuBarLinkedEventsOnly: Bool {
        didSet {
            defaults.set(
                menuBarLinkedEventsOnly, forKey: Key.menuBarLinkedEventsOnly.rawValue)
        }
    }

    var hideCurrentEvent: HideCurrentEvent {
        didSet { defaults.set(hideCurrentEvent.rawValue, forKey: Key.hideCurrentEvent.rawValue) }
    }

    /// Off means fully off: no launcher entries, and a still-registered shortcut moves nothing.
    var windowManagementEnabled: Bool {
        didSet {
            defaults.set(windowManagementEnabled, forKey: Key.windowManagementEnabled.rawValue)
        }
    }

    var windowManagementShowInLauncher: Bool {
        didSet {
            defaults.set(
                windowManagementShowInLauncher,
                forKey: Key.windowManagementShowInLauncher.rawValue)
        }
    }

    /// Points between tiled windows and the screen edge; `WindowLayout` caps it.
    var windowGap: Int {
        didSet { defaults.set(windowGap, forKey: Key.windowGap.rawValue) }
    }

    /// Re-triggering a half steps it through ⅓ and ⅔ instead of re-applying the same frame.
    var windowCycleOnRepeat: Bool {
        didSet { defaults.set(windowCycleOnRepeat, forKey: Key.windowCycleOnRepeat.rawValue) }
    }

    /// Off means fully off, down to a still-registered shortcut opening nothing.
    var quicklinksEnabled: Bool {
        didSet { defaults.set(quicklinksEnabled, forKey: Key.quicklinksEnabled.rawValue) }
    }

    var quicklinksShowInLauncher: Bool {
        didSet {
            defaults.set(quicklinksShowInLauncher, forKey: Key.quicklinksShowInLauncher.rawValue)
        }
    }

    /// Ask for a new window rather than a tab; off is the macOS default.
    var quicklinkOpensNewWindow: Bool {
        didSet {
            defaults.set(quicklinkOpensNewWindow, forKey: Key.quicklinkOpensNewWindow.rawValue)
        }
    }

    /// What `{selection}` does when there is no readable selection to pass.
    var quicklinkSelectionFallback: QuicklinkSelectionFallback {
        didSet {
            defaults.set(
                quicklinkSelectionFallback.rawValue,
                forKey: Key.quicklinkSelectionFallback.rawValue)
        }
    }

    var quicklinkConfirmsBeforeDelete: Bool {
        didSet {
            defaults.set(
                quicklinkConfirmsBeforeDelete, forKey: Key.quicklinkConfirmsBeforeDelete.rawValue)
        }
    }

    /// Whether the support window may reopen itself; off means never ask again.
    var supportRemindersEnabled: Bool {
        didSet { defaults.set(supportRemindersEnabled, forKey: Key.supportReminders.rawValue) }
    }

    init() {
        // The only feature switch that defaults on, so absence has to outrank a stored `false`.
        clipboardEnabled =
            defaults.object(forKey: Key.clipboardEnabled.rawValue) == nil
            || defaults.bool(forKey: Key.clipboardEnabled.rawValue)
        // `integer(forKey:)` returns 0 when unset, which no case matches.
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention.rawValue))
            ?? .threeMonths
        // Password managers ship excluded, until the user first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps.rawValue)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        launchAtLogin = LaunchAtLogin.isEnabled
        hyperKey =
            defaults.string(forKey: Key.hyperKey.rawValue).flatMap(HyperKeyPhysicalKey.init)
            ?? .none
        // Defaults to true, so absence must be distinguished from a stored `false`.
        hyperKeyIncludesShift =
            defaults.object(forKey: Key.hyperKeyIncludesShift.rawValue) == nil
            || defaults.bool(forKey: Key.hyperKeyIncludesShift.rawValue)
        hyperKeyQuickPress =
            defaults.string(forKey: Key.hyperKeyQuickPress.rawValue)
            .flatMap(HyperKeyQuickPress.init)
            ?? .none
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone.rawValue).flatMap(EmojiSkinTone.init) ?? .none
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout.rawValue))
            ?? .immediately
        appearance =
            defaults.string(forKey: Key.appearance.rawValue).flatMap(AppAppearance.init) ?? .system
        compactMode = defaults.bool(forKey: Key.compactMode.rawValue)
        // Defaults to true, so absence must be distinguished from a stored `false`.
        showFavoritesInCompactMode =
            defaults.object(forKey: Key.showFavoritesInCompactMode.rawValue) == nil
            || defaults.bool(forKey: Key.showFavoritesInCompactMode.rawValue)
        // Unset seeds the defaults; a stored empty array is a deliberately cleared list.
        searchScopes =
            defaults.stringArray(forKey: Key.searchScopes.rawValue) ?? SearchScopes.defaults
        openOnCursorScreen =
            defaults.object(forKey: Key.openOnCursorScreen.rawValue) == nil
            || defaults.bool(forKey: Key.openOnCursorScreen.rawValue)
        autoSwitchInputSourceID = defaults.string(forKey: Key.autoSwitchInputSource.rawValue)
        paletteDraggable = defaults.bool(forKey: Key.paletteDraggable.rawValue)
        // A half-written pair is no position at all, so both coordinates have to be there.
        palettePosition = (defaults.array(forKey: Key.palettePosition.rawValue) as? [Double])
            .flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        fileSearchEnabled = defaults.bool(forKey: Key.fileSearchEnabled.rawValue)
        // Unset seeds home; a stored empty array is a cleared list that searches nothing.
        fileSearchScopes =
            defaults.stringArray(forKey: Key.fileSearchScopes.rawValue)
            ?? FileSearchScope.defaultScopes
        fileSearchIgnorePatterns =
            defaults.stringArray(forKey: Key.fileSearchIgnorePatterns.rawValue) ?? []
        notesEnabled = defaults.bool(forKey: Key.notesEnabled.rawValue)
        aiEnabled = defaults.bool(forKey: Key.aiEnabled.rawValue)
        mcpEnabled = defaults.bool(forKey: Key.mcpEnabled.rawValue)
        customCommandsEnabled = defaults.bool(forKey: Key.customCommandsEnabled.rawValue)
        // These default on, so absence must be distinguished from a stored `false`.
        customCommandsShowInLauncher =
            defaults.object(forKey: Key.customCommandsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.customCommandsShowInLauncher.rawValue)
        snippetsEnabled = defaults.bool(forKey: Key.snippetsEnabled.rawValue)
        quickActionsEnabled = defaults.bool(forKey: Key.quickActionsEnabled.rawValue)
        snippetsShowInLauncher =
            defaults.object(forKey: Key.snippetsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.snippetsShowInLauncher.rawValue)
        // Opt-in, unlike its siblings: until it is asked for, nothing about extensions is loaded.
        extensionsEnabled = defaults.bool(forKey: Key.extensionsEnabled.rawValue)
        extensionsShowInLauncher =
            defaults.object(forKey: Key.extensionsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.extensionsShowInLauncher.rawValue)
        extensionPackageManager =
            defaults.string(forKey: Key.extensionPackageManager.rawValue)
            .flatMap(ExtensionPackageManager.init(rawValue:)) ?? .automatic
        extensionRegistries =
            defaults.data(forKey: Key.extensionRegistries.rawValue)
            .flatMap { try? JSONDecoder().decode([ExtensionRegistry].self, from: $0) }
            ?? ExtensionRegistry.defaults
        extensionCustomSearchPaths =
            defaults.stringArray(forKey: Key.extensionCustomSearchPaths.rawValue) ?? []
        // Opt-in, like extensions: until it is asked for, EventKit is never loaded.
        calendarEnabled = defaults.bool(forKey: Key.calendarEnabled.rawValue)
        calendarShowInLauncher =
            defaults.object(forKey: Key.calendarShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.calendarShowInLauncher.rawValue)
        calendarLauncherLimit =
            defaults.object(forKey: Key.calendarLauncherLimit.rawValue)
            .flatMap { $0 as? Int }
            .flatMap(CalendarLauncherLimit.init(rawValue:)) ?? .three
        calendarIncludesTomorrow =
            defaults.object(forKey: Key.calendarIncludesTomorrow.rawValue) == nil
            || defaults.bool(forKey: Key.calendarIncludesTomorrow.rawValue)
        joinWindowMinutes =
            JoinWindow(rawValue: defaults.integer(forKey: Key.joinWindowMinutes.rawValue)) ?? .five
        autoJoinMeetings = defaults.bool(forKey: Key.autoJoinMeetings.rawValue)
        autoJoinConfirms =
            defaults.object(forKey: Key.autoJoinConfirms.rawValue) == nil
            || defaults.bool(forKey: Key.autoJoinConfirms.rawValue)
        cameraPreview = defaults.bool(forKey: Key.cameraPreview.rawValue)
        // Both default to their zero case, so an unset key needs no presence check.
        menuBarEvents =
            MenuBarEvents(rawValue: defaults.integer(forKey: Key.menuBarEvents.rawValue)) ?? .today
        calendarMenuBarDisplay =
            CalendarMenuBarDisplay(
                rawValue: defaults.integer(forKey: Key.calendarMenuBarDisplay.rawValue))
            ?? .disabled
        menuBarLinkedEventsOnly =
            defaults.object(forKey: Key.menuBarLinkedEventsOnly.rawValue) == nil
            || defaults.bool(forKey: Key.menuBarLinkedEventsOnly.rawValue)
        hideCurrentEvent =
            defaults.object(forKey: Key.hideCurrentEvent.rawValue)
            .flatMap { $0 as? Int }
            .flatMap(HideCurrentEvent.init(rawValue:)) ?? .dontHide
        windowManagementEnabled = defaults.bool(forKey: Key.windowManagementEnabled.rawValue)
        windowManagementShowInLauncher =
            defaults.object(forKey: Key.windowManagementShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowManagementShowInLauncher.rawValue)
        // Unset reads as 0, which is the intended default anyway — no gap.
        windowGap = defaults.integer(forKey: Key.windowGap.rawValue)
        windowCycleOnRepeat = defaults.bool(forKey: Key.windowCycleOnRepeat.rawValue)
        quicklinksEnabled = defaults.bool(forKey: Key.quicklinksEnabled.rawValue)
        quicklinksShowInLauncher =
            defaults.object(forKey: Key.quicklinksShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.quicklinksShowInLauncher.rawValue)
        quicklinkOpensNewWindow = defaults.bool(forKey: Key.quicklinkOpensNewWindow.rawValue)
        quicklinkSelectionFallback =
            defaults.string(forKey: Key.quicklinkSelectionFallback.rawValue)
            .flatMap(QuicklinkSelectionFallback.init) ?? .ask
        quicklinkConfirmsBeforeDelete =
            defaults.object(forKey: Key.quicklinkConfirmsBeforeDelete.rawValue) == nil
            || defaults.bool(forKey: Key.quicklinkConfirmsBeforeDelete.rawValue)
        supportRemindersEnabled =
            defaults.object(forKey: Key.supportReminders.rawValue) == nil
            || defaults.bool(forKey: Key.supportReminders.rawValue)
    }
}
