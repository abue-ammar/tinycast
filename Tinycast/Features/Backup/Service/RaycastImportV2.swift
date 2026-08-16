import AppKit
import CryptoKit
import Foundation

/// Decrypts and maps a Raycast X export. See docs/features/raycast-import.md.
enum RaycastImportV2 {
    static func read(_ raw: Data, passphrase: String) throws -> RaycastImport.Result {
        try parse(decrypt(raw, passphrase: passphrase))
    }

    // MARK: - Decrypt

    static func decrypt(_ raw: Data, passphrase: String) throws -> Data {
        guard let envelopeData = try? Zlib.gunzip(raw),
            let env = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
            let dataHex = env["data"] as? String,
            let enc = env["encryption"] as? [String: String],
            let iv = enc["iv"].flatMap(Data.init(hex:)),
            let salt = enc["salt"].flatMap(Data.init(hex:)),
            let tag = enc["authTag"].flatMap(Data.init(hex:)),
            let ciphertext = Data(hex: dataHex)
        else { throw RaycastImportError.notRaycastFile }

        let key = Scrypt.derive(
            passphrase: Array(passphrase.utf8), salt: [UInt8](salt), n: 16384, r: 8, p: 1, dkLen: 32)

        let plaintextGz: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: iv), ciphertext: ciphertext, tag: tag)
            plaintextGz = try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw RaycastImportError.incorrectPassphrase
        }
        guard let plaintext = try? Zlib.gunzip(plaintextGz) else {
            throw RaycastImportError.corrupt
        }
        return plaintext
    }

    // MARK: - Map

    static func parse(_ decrypted: Data) throws -> RaycastImport.Result {
        guard let json = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] else {
            throw RaycastImportError.corrupt
        }
        var backup = SettingsBackup()
        backup.settings = mapSettings(json)
        backup.hotkeys = mapHotkeys(json)
        backup.favoriteApps = mapFavorites(json)
        let (clipboard, missing) = mapClipboard(json)
        let snippets = RaycastSnippetImport.parse(
            (json["builtin_package_snippets"] as? [String: Any])?["snippets"])
        return RaycastImport.Result(
            backup: backup,
            clipboard: clipboard,
            snippets: snippets,
            missingImages: missing)
    }

    /// Raycast's hyper key code → ours; nothing maps to `.none`, so none is cleared.
    private static let hyperKeyCodes: [String: HyperKeyPhysicalKey] = [
        "caps_lock": .capsLock,
        "right_control": .rightControl,
        "right_shift": .rightShift,
        "right_option": .rightOption,
        "right_command": .rightCommand
    ]

    private static func mapSettings(_ json: [String: Any]) -> SettingsBackup.SettingsData? {
        let general = (json["settings"] as? [String: Any])?["general"] as? [String: Any]
        var data = SettingsBackup.SettingsData()
        var mapped = false
        if let openAtLogin = general?["openAtLogin"] as? Bool {
            data.launchAtLogin = openAtLogin
            mapped = true
        }
        if let includeShift = general?["hyperKeyIncludeShift"] as? Bool {
            data.hyperKeyIncludesShift = includeShift
            mapped = true
        }
        // Without the physical key the imported chord shortcuts can't be triggered.
        if let code = general?["hyperKeyCode"] as? String, let key = hyperKeyCodes[code] {
            data.hyperKey = key.rawValue
            mapped = true
        }
        if let showInMenuBar = general?["showInMenuBar"] as? Bool {
            data.showInMenuBar = showInMenuBar
            mapped = true
        }
        if let tone = mapSkinTone(json) {
            data.emojiSkinTone = tone
            mapped = true
        }
        // Exact-match only: a timeout outside our option set is skipped, not clamped.
        if let secs = general?["popToRootTimeout"] as? Int,
            let timeout = PopToRootTimeout(rawValue: secs)
        {
            data.popToRootSeconds = timeout.rawValue
            mapped = true
        }
        // Raycast's window mode is a string; we only have the compact toggle.
        if let mode = general?["windowMode"] as? String {
            data.compactMode = (mode == "compact")
            mapped = true
        }
        if let showFavorites = general?["showFavoritesInCompactMode"] as? Bool {
            data.showFavoritesInCompactMode = showFavorites
            mapped = true
        }
        return mapped ? data : nil
    }

    /// Every Raycast hotkey, in one shape. See docs/features/raycast-import.md.
    private static func mapHotkeys(_ json: [String: Any]) -> SettingsBackup.HotkeyBackup? {
        let settings = json["settings"] as? [String: Any]
        var hotkeys = SettingsBackup.HotkeyBackup()
        var apps: [String: HotKeyBinding] = [:]
        var mapped = false

        if let general = settings?["general"] as? [String: Any],
            let binding = binding(from: general["globalHotkey"])
        {
            hotkeys.togglePalette = binding
            mapped = true
        }

        for command in settings?["commands"] as? [[String: Any]] ?? [] {
            guard let binding = binding(from: command["macosHotkey"]) else { continue }
            switch command["extensionId"] as? String {
            case "e:r:clipboard-history":
                hotkeys.toggleClipboard = binding
                mapped = true
            case "e:r:emoji-picker":
                hotkeys.toggleEmoji = binding
                mapped = true
            case "e:r:applications":
                if let path = appPath(fromCommandID: command["id"] as? String),
                    let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
                {
                    apps[bundleID] = binding
                    mapped = true
                }
            default:
                break
            }
        }
        if !apps.isEmpty { hotkeys.apps = apps }
        return mapped ? hotkeys : nil
    }

    /// A binding from a Raycast hotkey; always a `.combo`, Raycast having no double-tap.
    private static func binding(from hotkey: Any?) -> HotKeyBinding? {
        guard let dict = hotkey as? [String: Any],
            let shortcut = (dict["kind"] as? [String: Any])?["shortcut"] as? [String: Any],
            let key = shortcut["key"] as? [String: Any],
            (key["type"] as? String) == "LayoutIndependent",
            let code = key["code"] as? Int
        else { return nil }

        var flags: NSEvent.ModifierFlags = []
        for entry in (shortcut["modifiers"] as? [[String: Any]]) ?? [] {
            switch entry["modifier"] as? String {
            case "Meta": flags.insert(.command)
            case "Ctrl": flags.insert(.control)
            case "Alt": flags.insert(.option)
            case "Shift": flags.insert(.shift)
            default: break
            }
        }
        return .combo(
            KeyShortcut(
                carbonKeyCode: code, carbonModifiers: KeyShortcut.carbonModifiers(from: flags)))
    }

    /// Only app favorites map over, keyed by bundle ID, preserving Raycast's order.
    private static func mapFavorites(_ json: [String: Any]) -> [String]? {
        guard let commands = (json["settings"] as? [String: Any])?["commands"] as? [[String: Any]]
        else { return nil }
        let favorites =
            commands
            .compactMap { command -> (order: Int, bundleID: String)? in
                guard let order = command["favoriteOrder"] as? Int,
                    command["extensionId"] as? String == "e:r:applications",
                    let path = appPath(fromCommandID: command["id"] as? String),
                    let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
                else { return nil }
                return (order, bundleID)
            }
            .sorted { $0.order < $1.order }
            .map(\.bundleID)
        return favorites.isEmpty ? nil : favorites
    }

    /// The launched app's path is the tail of an applications command id.
    private static func appPath(fromCommandID id: String?) -> String? {
        guard let id, let range = id.range(of: "::=::") else { return nil }
        let path = String(id[range.upperBound...])
        return path.isEmpty ? nil : path
    }

    /// A recursive search, avoiding a brittle path; the raw values line up already.
    private static func mapSkinTone(_ json: [String: Any]) -> String? {
        guard let raw = firstValue(forKey: "skinTone", in: json) as? String else { return nil }
        if raw == "default" { return EmojiSkinTone.none.rawValue }
        return EmojiSkinTone(rawValue: raw)?.rawValue
    }

    // MARK: - Clipboard

    private static func mapClipboard(_ json: [String: Any]) -> (items: [ClipboardItem], missing: Int) {
        guard
            let entries = (json["clipboardHistory"] as? [String: Any])?["clipboardEntries"]
                as? [[String: Any]]
        else { return ([], 0) }

        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var items: [ClipboardItem] = []
        var missing = 0
        for entry in entries {
            let createdAt = parseDate(entry["createdAt"] as? String, using: dateParser) ?? Date()
            let reps = (entry["items"] as? [[String: Any]] ?? [])
                .flatMap { ($0["representations"] as? [[String: Any]]) ?? [] }

            if let text = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("text/plain") == true
            })?["content"] as? String, !text.isEmpty {
                items.append(
                    ClipboardItem(
                        id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: createdAt,
                        sourceBundleID: nil))
                continue
            }

            if let path = reps.first(where: {
                ($0["mimeType"] as? String)?.hasPrefix("image/") == true
                    && ($0["contentType"] as? String) == "url"
            })?["content"] as? String {
                guard FileManager.default.fileExists(atPath: path) else {
                    missing += 1
                    continue
                }
                items.append(
                    ClipboardItem(imagePath: path, createdAt: createdAt, sourceBundleID: nil))
            }
        }
        return (items, missing)
    }

    // MARK: - Helpers

    private static func parseDate(_ string: String?, using parser: ISO8601DateFormatter) -> Date? {
        guard let string else { return nil }
        // Fractional-seconds parser first; fall back to a whole-second timestamp.
        return parser.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    /// First value stored under `key` anywhere in a nested JSON object/array tree.
    private static func firstValue(forKey key: String, in object: Any) -> Any? {
        if let dict = object as? [String: Any] {
            if let hit = dict[key] { return hit }
            for value in dict.values {
                if let hit = firstValue(forKey: key, in: value) { return hit }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let hit = firstValue(forKey: key, in: value) { return hit }
            }
        }
        return nil
    }
}

extension Data {
    /// Parses an even-length hex string; returns nil on any non-hex character.
    init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x61...0x66: return c - 0x61 + 10
            case 0x41...0x46: return c - 0x41 + 10
            default: return nil
            }
        }
        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            bytes.append(hi << 4 | lo)
            i += 2
        }
        self = Data(bytes)
    }
}
