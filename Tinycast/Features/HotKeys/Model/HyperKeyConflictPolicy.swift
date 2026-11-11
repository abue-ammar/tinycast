import Foundation

/// What counts as fighting the Hyper Key. Pure, so the app and `HyperKeyTests` read one rule.
enum HyperKeyConflictPolicy {
    enum Severity: String, Sendable {
        case blocking
        /// The app may remap the same keys; reported, never acted on.
        case warning
    }

    struct KnownApp: Sendable {
        let bundleID: String
        let severity: Severity
    }

    struct KeyboardIdentity: Hashable, Sendable {
        let vendorID: Int
        let productID: Int

        /// The `0-0-0` entry, which applies to every keyboard without its own.
        var isDefault: Bool { vendorID == 0 && productID == 0 }
    }

    static let knownApps: [KnownApp] = [
        KnownApp(bundleID: "com.hegenberg.BetterTouchTool", severity: .warning),
        KnownApp(bundleID: "com.knollsoft.Hyperkey", severity: .blocking),
        KnownApp(bundleID: "com.knollsoft.Superkey", severity: .blocking),
        KnownApp(bundleID: "com.raycast.macos", severity: .warning)
    ]

    /// Average time another app's keyboard tap holds each event before typing visibly lags.
    static let slowTapMicroseconds: Float = 50_000

    static let secureInputSuspects: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword",
        "com.bitwarden.desktop", "org.keepassxc.keepassxc", "com.googlecode.iterm2",
        "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "com.github.wez.wezterm"
    ]

    static let modifierMappingPrefix = "com.apple.keyboard.modifiermapping."

    static func severity(ofBundleID bundleID: String) -> Severity? {
        knownApps.first { $0.bundleID == bundleID }?.severity
    }

    static func isKarabinerVirtualKeyboard(named name: String) -> Bool {
        name.hasPrefix("Karabiner DriverKit VirtualHIDKeyboard")
    }

    static func capsLockRemaps(in preferences: [String: Any]) -> [KeyboardIdentity] {
        preferences.compactMap { key, value in
            guard key.hasPrefix(modifierMappingPrefix),
                HIDKeyMapping.mappings(from: value).contains(where: movesCapsLock)
            else { return nil }
            return keyboardIdentity(fromSuffix: String(key.dropFirst(modifierMappingPrefix.count)))
        }
        .sorted { ($0.vendorID, $0.productID) < ($1.vendorID, $1.productID) }
    }

    /// `key` is a `HyperKeyPhysicalKey` raw value, matched against the selected profile.
    static func karabinerRemaps(_ key: String, config: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: config) as? [String: Any],
            let profiles = root["profiles"] as? [[String: Any]]
        else { return false }
        let keyCode = karabinerKeyCode(for: key)
        let selected = profiles.filter { $0["selected"] as? Bool == true }
        return (selected.isEmpty ? profiles : selected).contains { profile in
            remappedKeyCodes(in: profile).contains(keyCode)
        }
    }

    /// Karabiner's file spells key codes in snake case, so `capsLock` is `caps_lock` there.
    private static func karabinerKeyCode(for key: String) -> String {
        key.reduce(into: "") { code, character in
            if character.isUppercase { code.append("_") }
            code.append(Character(character.lowercased()))
        }
    }

    private static func movesCapsLock(_ mapping: HIDKeyMapping) -> Bool {
        mapping.source == HIDKeyMapping.capsLock && mapping.destination != mapping.source
    }

    /// `vendor-product-…`; an empty suffix is the default entry.
    private static func keyboardIdentity(fromSuffix suffix: String) -> KeyboardIdentity? {
        guard !suffix.isEmpty else { return KeyboardIdentity(vendorID: 0, productID: 0) }
        let parts = suffix.split(separator: "-").map { Int($0) }
        guard parts.count >= 2, let vendorID = parts[0], let productID = parts[1] else { return nil }
        return KeyboardIdentity(vendorID: vendorID, productID: productID)
    }

    private static func remappedKeyCodes(in profile: [String: Any]) -> Set<String> {
        let devices = profile["devices"] as? [[String: Any]] ?? []
        let simple = ([profile] + devices).flatMap {
            $0["simple_modifications"] as? [[String: Any]] ?? []
        }
        let rules =
            (profile["complex_modifications"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        let manipulators = rules.flatMap { $0["manipulators"] as? [[String: Any]] ?? [] }
        return Set((simple + manipulators).compactMap { fromKeyCode(of: $0) })
    }

    private static func fromKeyCode(of modification: [String: Any]) -> String? {
        (modification["from"] as? [String: Any])?["key_code"] as? String
    }
}
