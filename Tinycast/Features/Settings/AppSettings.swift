import SwiftUI

/// Keys shared between `@AppStorage` sites, so app and Settings bind to the same one.
enum SettingsKey {
    /// Menu-bar icon visibility — read by `MenuBarExtra(isInserted:)` and the Settings toggle.
    static let showInMenuBar = "showInMenuBar"
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

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    private typealias Key = AppSettingsKey

    /// What `AppIndex` scans, in scan order; editing it re-indexes, being observed.
    var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes.rawValue) }
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

    /// Where a drag left the panel's top-left, in screen coordinates; nil means the default placement.
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

    var snippetsShowInLauncher: Bool {
        didSet { defaults.set(snippetsShowInLauncher, forKey: Key.snippetsShowInLauncher.rawValue) }
    }

    /// Also consent to run third-party JavaScript, and the one feature with a standing memory cost,
    /// so it confirms first, defaults off and never rides a backup.
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

    /// Where extensions are searched for. Seeded with the store and the official repository; a user
    /// can add their own, which is the point of it being a list rather than a flag.
    var extensionRegistries: [ExtensionRegistry] {
        didSet {
            guard let data = try? JSONEncoder().encode(extensionRegistries) else { return }
            defaults.set(data, forKey: Key.extensionRegistries.rawValue)
        }
    }

    /// Extra PATH folders searched before the built-in list, for a toolchain in a place Tinycast
    /// doesn't already know — mise or Nix shims are the common case. Empty means nothing extra.
    var extensionCustomSearchPaths: [String] {
        didSet {
            defaults.set(
                extensionCustomSearchPaths, forKey: Key.extensionCustomSearchPaths.rawValue)
        }
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

    init() {
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
        // Unset seeds home; a stored empty array is a deliberately cleared list that searches nothing.
        fileSearchScopes =
            defaults.stringArray(forKey: Key.fileSearchScopes.rawValue)
            ?? FileSearchScope.defaultScopes
        fileSearchIgnorePatterns =
            defaults.stringArray(forKey: Key.fileSearchIgnorePatterns.rawValue) ?? []
        notesEnabled = defaults.bool(forKey: Key.notesEnabled.rawValue)
        customCommandsEnabled = defaults.bool(forKey: Key.customCommandsEnabled.rawValue)
        // These default on, so absence must be distinguished from a stored `false`.
        customCommandsShowInLauncher =
            defaults.object(forKey: Key.customCommandsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.customCommandsShowInLauncher.rawValue)
        snippetsEnabled = defaults.bool(forKey: Key.snippetsEnabled.rawValue)
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
    }
}
