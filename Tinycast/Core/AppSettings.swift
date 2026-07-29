import SwiftUI

/// UserDefaults keys shared between `@AppStorage` call sites so the App and the Settings UI bind to the same key.
enum SettingsKey {
    /// Menu-bar icon visibility — read by `MenuBarExtra(isInserted:)` and the Settings toggle.
    static let showInMenuBar = "showInMenuBar"
}

/// Delay before a closed palette resets to the root launcher; raw value is seconds in UserDefaults, so an unset key (0) reads as `.immediately`, the default.
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
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Key {
        static let clipboardRetention = "clipboardRetentionDays"
        static let clipboardDisabledApps = "clipboardDisabledApps"
        static let hyperKey = "hyperKeyPhysicalKey"
        static let hyperKeyIncludesShift = "hyperKeyIncludesShift"
        static let hyperKeyQuickPress = "hyperKeyQuickPress"
        static let hyperKeyReplacesGlyph = "hyperKeyReplacesGlyph"
        static let emojiSkinTone = "emojiSkinTone"
        static let popToRootTimeout = "popToRootTimeout"
        static let compactMode = "compactMode"
        static let showFavoritesInCompactMode = "showFavoritesInCompactMode"
        static let searchScopes = "launcherSearchScopes"
        static let openOnCursorScreen = "openOnCursorScreen"
    }

    /// Folders (and individual `.app` bundles) `AppIndex` scans, in scan order. Editing this re-indexes — `AppIndex.start(settings:)` observes it.
    @Published var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes) }
    }

    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention) }
    }

    /// Bundle IDs whose clipboard changes are never recorded. Ordered so the Settings list is stable.
    @Published var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps) }
    }

    @Published var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    /// The physical key remapped to the Hyper chord; `HyperKeyTap` reacts via its publisher.
    @Published var hyperKey: HyperKeyPhysicalKey {
        didSet { defaults.set(hyperKey.rawValue, forKey: Key.hyperKey) }
    }

    /// Whether Hyper is ⌃⌥⇧⌘ (on) or ⌃⌥⌘ (off).
    @Published var hyperKeyIncludesShift: Bool {
        didSet { defaults.set(hyperKeyIncludesShift, forKey: Key.hyperKeyIncludesShift) }
    }

    @Published var hyperKeyQuickPress: HyperKeyQuickPress {
        didSet { defaults.set(hyperKeyQuickPress.rawValue, forKey: Key.hyperKeyQuickPress) }
    }

    /// Collapse the Hyper modifier set to "✦" wherever shortcut keycaps render.
    @Published var hyperKeyReplacesGlyph: Bool {
        didSet { defaults.set(hyperKeyReplacesGlyph, forKey: Key.hyperKeyReplacesGlyph) }
    }

    /// Preferred skin tone applied to modifier-capable emoji at render and copy time.
    @Published var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone) }
    }

    /// How long a closed palette keeps its state before popping back to the root launcher.
    @Published var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout) }
    }

    /// Summon the launcher as a slim search bar that expands into the full list on typing.
    @Published var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode) }
    }

    /// Pin favorite app icons to the right of the compact search bar (⌘1–⌘5 to launch).
    @Published var showFavoritesInCompactMode: Bool {
        didSet { defaults.set(showFavoritesInCompactMode, forKey: Key.showFavoritesInCompactMode) }
    }

    /// Summon the palette on the display under the pointer instead of the one holding the menu bar.
    @Published var openOnCursorScreen: Bool {
        didSet { defaults.set(openOnCursorScreen, forKey: Key.openOnCursorScreen) }
    }

    init() {
        // integer(forKey:) returns 0 when unset, which no case matches — falls through to 3 Months.
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention))
            ?? .threeMonths
        // Password managers are excluded out of the box; the defaults apply only until the user first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        launchAtLogin = LaunchAtLogin.isEnabled
        hyperKey =
            defaults.string(forKey: Key.hyperKey).flatMap(HyperKeyPhysicalKey.init) ?? .none
        // The two Bools default to true, so absence must be distinguished from stored `false`.
        hyperKeyIncludesShift =
            defaults.object(forKey: Key.hyperKeyIncludesShift) == nil
            || defaults.bool(forKey: Key.hyperKeyIncludesShift)
        hyperKeyQuickPress =
            defaults.string(forKey: Key.hyperKeyQuickPress).flatMap(HyperKeyQuickPress.init)
            ?? .none
        hyperKeyReplacesGlyph =
            defaults.object(forKey: Key.hyperKeyReplacesGlyph) == nil
            || defaults.bool(forKey: Key.hyperKeyReplacesGlyph)
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone).flatMap(EmojiSkinTone.init) ?? .none
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout))
            ?? .immediately
        compactMode = defaults.bool(forKey: Key.compactMode)
        // Defaults to true, so absence must be distinguished from a stored `false`.
        showFavoritesInCompactMode =
            defaults.object(forKey: Key.showFavoritesInCompactMode) == nil
            || defaults.bool(forKey: Key.showFavoritesInCompactMode)
        // An unset key means "never configured" and seeds the defaults; a stored empty array is a user who deliberately cleared the list.
        searchScopes = defaults.stringArray(forKey: Key.searchScopes) ?? SearchScopes.defaults
        openOnCursorScreen =
            defaults.object(forKey: Key.openOnCursorScreen) == nil
            || defaults.bool(forKey: Key.openOnCursorScreen)
    }
}
