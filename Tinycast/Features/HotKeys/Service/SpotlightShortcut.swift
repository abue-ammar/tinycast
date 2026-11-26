import AppKit

/// Spotlight's own shortcut: a macOS symbolic hotkey, which answers before any app's registration.
@MainActor
enum SpotlightShortcut {
    private static let symbolicHotKeyID: UInt32 = 64
    private static let skyLight = SymbolicHotKeyFunctions()

    static var current: KeyShortcut? {
        guard let skyLight, skyLight.isEnabled(symbolicHotKeyID) else { return nil }
        var character: UInt16 = 0
        var keyCode: UInt16 = 0
        var modifiers: UInt32 = 0
        guard skyLight.getValue(symbolicHotKeyID, &character, &keyCode, &modifiers) == .success
        else { return nil }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        return KeyShortcut(
            carbonKeyCode: Int(keyCode), carbonModifiers: KeyShortcut.carbonModifiers(from: flags))
    }

    /// Changes the live state and the saved one, which macOS restores at login.
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard let skyLight, skyLight.setEnabled(symbolicHotKeyID, enabled) == .success else {
            return false
        }
        if savePreference(enabled: enabled) { return true }
        _ = skyLight.setEnabled(symbolicHotKeyID, !enabled)
        return false
    }

    private static func savePreference(enabled: Bool) -> Bool {
        let domain = "com.apple.symbolichotkeys" as CFString
        let key = "AppleSymbolicHotKeys" as CFString
        let entryKey = String(symbolicHotKeyID)
        var hotKeys =
            CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String: Any] ?? [:]
        var entry = hotKeys[entryKey] as? [String: Any] ?? [:]
        entry["enabled"] = enabled
        hotKeys[entryKey] = entry
        CFPreferencesSetValue(
            key, hotKeys as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

private struct SymbolicHotKeyFunctions {
    typealias IsEnabled = @convention(c) (UInt32) -> Bool
    typealias GetValue =
        @convention(c) (
            UInt32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>,
            UnsafeMutablePointer<UInt32>
        ) -> CGError
    typealias SetEnabled = @convention(c) (UInt32, Bool) -> CGError

    let isEnabled: IsEnabled
    let getValue: GetValue
    let setEnabled: SetEnabled

    init?() {
        guard
            let skyLight = dlopen(
                "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
            let isEnabled = dlsym(skyLight, "SLSIsSymbolicHotKeyEnabled"),
            let getValue = dlsym(skyLight, "SLSGetSymbolicHotKeyValue"),
            let setEnabled = dlsym(skyLight, "SLSSetSymbolicHotKeyEnabled")
        else { return nil }
        self.isEnabled = unsafeBitCast(isEnabled, to: IsEnabled.self)
        self.getValue = unsafeBitCast(getValue, to: GetValue.self)
        self.setEnabled = unsafeBitCast(setEnabled, to: SetEnabled.self)
    }
}
