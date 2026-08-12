import Foundation

/// Temporary: adopts the pre-`hotkey.<action>` records, and is scheduled for deletion.
enum LegacyHotKeyRecords {
    private struct Combo: Decodable {
        let carbonKeyCode: Int
        let carbonModifiers: Int
    }

    private struct DoubleTap: Decodable {
        let doubleTapModifier: DoubleTapModifier
    }

    /// Consumes each old record, so the second launch finds nothing and this becomes a no-op.
    static func adopt(_ actions: [HotKeyAction], decoder: JSONDecoder, encoder: JSONEncoder) {
        let defaults = UserDefaults.standard
        for action in actions {
            guard let legacy = legacyKey(for: action) else { continue }
            guard let json = defaults.string(forKey: legacy), let data = json.data(using: .utf8)
            else { continue }
            defaults.removeObject(forKey: legacy)
            // Never clobber a binding already set under the new key: that one is the user's intent.
            guard defaults.string(forKey: action.defaultsKey) == nil,
                let binding = binding(from: data, decoder),
                let encoded = try? encoder.encode(binding),
                let rewritten = String(data: encoded, encoding: .utf8)
            else { continue }
            defaults.set(rewritten, forKey: action.defaultsKey)
        }
    }

    /// The two shapes `HotKeyBinding` used to write, flat combo first as that is what 0.7.5 stored.
    private static func binding(from data: Data, _ decoder: JSONDecoder) -> HotKeyBinding? {
        if let combo = try? decoder.decode(Combo.self, from: data) {
            return .combo(
                KeyShortcut(
                    carbonKeyCode: combo.carbonKeyCode, carbonModifiers: combo.carbonModifiers))
        }
        if let tap = try? decoder.decode(DoubleTap.self, from: data) {
            return .doubleTap(tap.doubleTapModifier)
        }
        return nil
    }

    /// Nil for an action that postdates the old scheme: it has no record to adopt, only a new key.
    private static func legacyKey(for action: HotKeyAction) -> String? {
        switch action {
        case .togglePalette: "KeyboardShortcuts_togglePalette"
        case .toggleClipboard: "KeyboardShortcuts_toggleClipboard"
        case .toggleEmoji: "KeyboardShortcuts_toggleEmoji"
        case .searchFiles: nil
        case .app(let bundleID): "KeyboardShortcuts_appHotkey." + bundleID
        case .settingsPane(let bundleID): "KeyboardShortcuts_paneHotkey." + bundleID
        case .customCommand(let id):
            "KeyboardShortcuts_customCommandHotkey." + id.uuidString.lowercased()
        case .systemAction(let id): "KeyboardShortcuts_systemActionHotkey." + id.rawValue
        case .windowCommand(let id): "KeyboardShortcuts_windowCommandHotkey." + id.rawValue
        case .quicklink(let id):
            "KeyboardShortcuts_quicklinkHotkey." + id.uuidString.lowercased()
        // Newer than the package it adopts records from, so there is nothing to adopt.
        case .extensionCommand: nil
        }
    }
}
