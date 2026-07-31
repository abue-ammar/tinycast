import AppKit
import CryptoKit
import Foundation

enum RaycastImportError: LocalizedError {
    case notRaycastFile
    case incorrectPassphrase
    case corrupt

    var errorDescription: String? {
        switch self {
        case .notRaycastFile: return "This doesn\u{2019}t look like a Raycast export (.rayconfig)."
        case .incorrectPassphrase: return "Incorrect passphrase, or the file is corrupted."
        case .corrupt: return "The Raycast export could not be read."
        }
    }
}

/// The independently importable categories in a Raycast export, so the user can pick a subset.
struct RaycastImportOptions: OptionSet, Sendable {
    let rawValue: Int
    static let shortcuts = RaycastImportOptions(rawValue: 1 << 0)
    static let favorites = RaycastImportOptions(rawValue: 1 << 1)
    static let emojiSkinTone = RaycastImportOptions(rawValue: 1 << 2)
    static let launchAtLogin = RaycastImportOptions(rawValue: 1 << 3)
    static let menuBarVisibility = RaycastImportOptions(rawValue: 1 << 4)
    static let clipboardHistory = RaycastImportOptions(rawValue: 1 << 5)
    static let popToRoot = RaycastImportOptions(rawValue: 1 << 6)
    static let compactMode = RaycastImportOptions(rawValue: 1 << 7)
    static let all: RaycastImportOptions = [
        .shortcuts, .favorites, .emojiSkinTone, .launchAtLogin, .menuBarVisibility, .clipboardHistory,
        .popToRoot, .compactMode,
    ]
}

/// Decrypts and parses a Raycast `.rayconfig` export. Supports two formats:
/// - v1 (Raycast 1.104.x+): a single AES-256-CBC ciphertext blob, key/IV derived from the
///   passphrase with OpenSSL's EVP_BytesToKey (SHA-256 / MD5, no salt), then a short prefix and
///   gzip stream containing a JSON object under `builtin_package_*` providers.
/// - v2 (upcoming / beta): gzip → JSON envelope → hex ciphertext decrypted with AES-256-GCM under a
///   scrypt(N=16384,r=8,p=1) key → gunzip → settings JSON.
/// Decrypt is CPU-heavy, so run it off the main actor.
enum RaycastImport {
    struct Result {
        var backup: SettingsBackup
        var clipboard: [ClipboardItem]
        /// Image clips whose referenced file no longer exists on disk (reported so the UI can note them).
        var missingImages: Int

        /// A copy trimmed to the chosen categories; `apply()` is already per-field non-destructive, so dropping a field is enough to skip it.
        func selecting(_ options: RaycastImportOptions) -> Result {
            var trimmed = SettingsBackup()
            if options.contains(.shortcuts) { trimmed.hotkeys = backup.hotkeys }
            if options.contains(.favorites) { trimmed.favoriteApps = backup.favoriteApps }

            var settings = SettingsBackup.SettingsData()
            var hasSettings = false
            if options.contains(.emojiSkinTone), let tone = backup.settings?.emojiSkinTone {
                settings.emojiSkinTone = tone
                hasSettings = true
            }
            if options.contains(.launchAtLogin), let launch = backup.settings?.launchAtLogin {
                settings.launchAtLogin = launch
                hasSettings = true
            }
            if options.contains(.menuBarVisibility), let show = backup.settings?.showInMenuBar {
                settings.showInMenuBar = show
                hasSettings = true
            }
            if options.contains(.popToRoot), let secs = backup.settings?.popToRootSeconds {
                settings.popToRootSeconds = secs
                hasSettings = true
            }
            if options.contains(.compactMode) {
                if let compact = backup.settings?.compactMode {
                    settings.compactMode = compact
                    hasSettings = true
                }
                if let showFavorites = backup.settings?.showFavoritesInCompactMode {
                    settings.showFavoritesInCompactMode = showFavorites
                    hasSettings = true
                }
            }
            if options.contains(.shortcuts) {
                if let shift = backup.settings?.hyperKeyIncludesShift {
                    settings.hyperKeyIncludesShift = shift
                    hasSettings = true
                }
                if let key = backup.settings?.hyperKey {
                    settings.hyperKey = key
                    hasSettings = true
                }
                if let glyph = backup.settings?.hyperKeyReplacesGlyph {
                    settings.hyperKeyReplacesGlyph = glyph
                    hasSettings = true
                }
            }
            if hasSettings { trimmed.settings = settings }

            let keepClipboard = options.contains(.clipboardHistory)
            return Result(
                backup: trimmed,
                clipboard: keepClipboard ? clipboard : [],
                missingImages: keepClipboard ? missingImages : 0)
        }
    }

    // MARK: - Decrypt

    static func decrypt(file: URL, passphrase: String) throws -> Data {
        let raw = try Data(contentsOf: file)
        guard !raw.isEmpty else { throw RaycastImportError.notRaycastFile }

        // v1 (current Raycast): a ciphertext blob, not a gzip.
        if let plaintext = try? decryptV1(raw, passphrase: passphrase, digest: .sha256),
           let json = try? extractJSONV1(from: plaintext) {
            return json
        }
        if let plaintext = try? decryptV1(raw, passphrase: passphrase, digest: .md5),
           let json = try? extractJSONV1(from: plaintext) {
            return json
        }

        // v2 (upcoming / beta): the file itself is a gzip-wrapped JSON envelope.
        if let data = try? decryptV2(raw, passphrase: passphrase) {
            return data
        }

        throw RaycastImportError.incorrectPassphrase
    }

    // MARK: - v1 (AES-256-CBC / EVP_BytesToKey)

    private static func decryptV1(_ raw: Data, passphrase: String, digest: DigestAlgorithm) throws -> Data {
        let (key, iv) = deriveKeyAndIV(passphrase: passphrase, digest: digest)

        let outputSize = raw.count + kCCBlockSizeAES128
        let output = UnsafeMutablePointer<UInt8>.allocate(capacity: outputSize)
        defer { output.deallocate() }

        var moved = 0
        let status = key.withUnsafeBytes { keyRaw in
            iv.withUnsafeBytes { ivRaw in
                raw.withUnsafeBytes { rawRaw in
                    cccrypt(
                        kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                        keyRaw.bindMemory(to: UInt8.self).baseAddress!, key.count,
                        ivRaw.bindMemory(to: UInt8.self).baseAddress!,
                        rawRaw.bindMemory(to: UInt8.self).baseAddress!, raw.count,
                        output, outputSize,
                        &moved)
                }
            }
        }

        guard status == kCCSuccess else { throw RaycastImportError.notRaycastFile }
        return Data(bytes: output, count: moved)
    }

    private static func extractJSONV1(from plaintext: Data) throws -> Data {
        guard let offset = plaintext.range(of: Data([0x1f, 0x8b, 0x08]))?.lowerBound,
              offset < plaintext.count
        else { throw RaycastImportError.notRaycastFile }
        return try Gunzip.decompress(plaintext[offset...])
    }

    // MARK: - v2 (gzip → JSON envelope → scrypt + AES-GCM)

    private static func decryptV2(_ raw: Data, passphrase: String) throws -> Data {
        guard let envelopeData = try? Gunzip.decompress(raw),
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
        guard let plaintext = try? Gunzip.decompress(plaintextGz) else {
            throw RaycastImportError.corrupt
        }
        return plaintext
    }

    // MARK: - Key derivation

    private enum DigestAlgorithm { case sha256, md5 }

    private static func deriveKeyAndIV(passphrase: String, digest: DigestAlgorithm) -> (key: Data, iv: Data) {
        let password = Data(passphrase.utf8)
        let digestFunc: (Data) -> Data = { data in
            switch digest {
            case .sha256: return Data(SHA256.hash(data: data))
            case .md5: return Data(Insecure.MD5.hash(data: data))
            }
        }

        var d = Data()
        var total = Data()
        while total.count < kCCKeySizeAES256 + kCCBlockSizeAES128 {
            var input = d
            input.append(password)
            d = digestFunc(input)
            total.append(d)
        }
        return (total.prefix(kCCKeySizeAES256), total.dropFirst(kCCKeySizeAES256).prefix(kCCBlockSizeAES128))
    }

    // MARK: - CommonCrypto AES-CBC

    private static let kCCDecrypt: UInt32 = 1
    private static let kCCAlgorithmAES: UInt32 = 0
    private static let kCCOptionPKCS7Padding: UInt32 = 1
    private static let kCCSuccess: Int32 = 0
    private static let kCCKeySizeAES256 = 32
    private static let kCCBlockSizeAES128 = 16

    @_silgen_name("CCCrypt")
    private static func cccrypt(
        _ op: UInt32, _ alg: UInt32, _ options: UInt32,
        _ key: UnsafePointer<UInt8>, _ keyLength: Int,
        _ iv: UnsafePointer<UInt8>?,
        _ dataIn: UnsafePointer<UInt8>, _ dataInLength: Int,
        _ dataOut: UnsafeMutablePointer<UInt8>, _ dataOutCapacity: Int,
        _ dataOutMoved: UnsafeMutablePointer<Int>
    ) -> Int32

    // MARK: - Map

    static func parse(_ decrypted: Data) throws -> Result {
        guard let json = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] else {
            throw RaycastImportError.corrupt
        }

        // v1 JSON uses provider packages under builtin_package_*.
        if json["builtin_package_raycastPreferences"] is [String: Any] {
            return parseV1(json)
        }

        // v2 JSON uses the flat settings / clipboardHistory envelope.
        if json["settings"] is [String: Any] {
            return parseV2(json)
        }

        throw RaycastImportError.corrupt
    }

    // MARK: - v1 mappers

    private static func parseV1(_ json: [String: Any]) -> Result {
        var backup = SettingsBackup()
        backup.settings = mapSettingsV1(json)
        backup.hotkeys = mapHotkeysV1(json)
        backup.favoriteApps = mapFavoritesV1(json)
        let (clipboard, missing) = mapClipboardV1(json)
        return Result(backup: backup, clipboard: clipboard, missingImages: missing)
    }

    private static func mapSettingsV1(_ json: [String: Any]) -> SettingsBackup.SettingsData? {
        let preferences = json["builtin_package_raycastPreferences"] as? [String: Any]
        let appearance = preferences?["preferencesAppearance"] as? [String: Any]
        let advanced = preferences?["preferencesAdvanced"] as? [String: Any]

        var data = SettingsBackup.SettingsData()
        var mapped = false

        if let secs = advanced?["popToRootTimeout"] as? Int, PopToRootTimeout(rawValue: secs) != nil {
            data.popToRootSeconds = secs
            mapped = true
        }

        // Raycast's window mode is a string ("compact"/"default"/...); Tinycast only has the compact toggle.
        if let mode = appearance?["raycastPreferredWindowMode"] as? String {
            data.compactMode = (mode == "compact")
            mapped = true
        }

        if let showFavorites = appearance?["showFavoritesInCompactMode"] as? Bool {
            data.showFavoritesInCompactMode = showFavorites
            mapped = true
        }

        if let tone = mapSkinTone(json) {
            data.emojiSkinTone = tone
            mapped = true
        }

        return mapped ? data : nil
    }

    private static func mapHotkeysV1(_ json: [String: Any]) -> SettingsBackup.HotkeyBackup? {
        let preferences = json["builtin_package_raycastPreferences"] as? [String: Any]
        let general = preferences?["preferencesGeneral"] as? [String: Any]

        var hotkeys = SettingsBackup.HotkeyBackup()
        var apps: [String: KeyShortcut] = [:]
        var mapped = false

        if let shortcut = keyShortcutV1(from: general?["raycastGlobalHotkey"]) {
            hotkeys.togglePalette = shortcut
            mapped = true
        }

        let rootSearch = (json["builtin_package_rootSearch"] as? [String: Any])?["rootSearch"] as? [[String: Any]] ?? []
        for command in rootSearch {
            guard let shortcut = keyShortcutV1(from: command["hotkey"]) else { continue }
            let key = command["key"] as? String

            if let key = key {
                if key == "builtin_command_clipboardHistory" {
                    hotkeys.toggleClipboard = shortcut
                    mapped = true
                    continue
                }
                if key.lowercased().contains("emoji") {
                    hotkeys.toggleEmoji = shortcut
                    mapped = true
                    continue
                }
            }

            if command["type"] as? String == "systemApp" {
                if let path = command["path"] as? String,
                   let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier {
                    apps[bundleID] = shortcut
                    mapped = true
                }
            }
        }

        if !apps.isEmpty { hotkeys.apps = apps }
        return mapped ? hotkeys : nil
    }

    /// Builds a `KeyShortcut` from a Raycast v1 hotkey string such as "Command-49" or "Shift-Command-7".
    /// The last component is a Carbon virtual keycode; the preceding components are modifier names.
    private static func keyShortcutV1(from hotkey: Any?) -> KeyShortcut? {
        guard let string = hotkey as? String else { return nil }
        let parts = string.split(separator: "-")
        guard let last = parts.last, let code = Int(last) else { return nil }

        var flags: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part.lowercased() {
            case "command", "cmd", "⌘", "meta": flags.insert(.command)
            case "shift", "⇧": flags.insert(.shift)
            case "option", "opt", "alt", "⌥": flags.insert(.option)
            case "ctrl", "control", "^": flags.insert(.control)
            default: break
            }
        }
        return KeyShortcut(keyCode: code, modifierFlags: flags)
    }

    private static func mapFavoritesV1(_ json: [String: Any]) -> [String]? {
        let pinned = (json["builtin_package_navigation"] as? [String: Any])?["pinnedMenuItems"] as? [Any] ?? []

        var favorites: [String] = []
        for item in pinned {
            var path: String?
            var bundleID: String?

            if let dict = item as? [String: Any] {
                path = dict["path"] as? String
                bundleID = dict["key"] as? String
            } else if let string = item as? String {
                if string.hasSuffix(".app") {
                    path = string
                } else if string.contains(".") {
                    bundleID = string
                }
            }

            if let path = path, let id = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier {
                favorites.append(id)
            } else if let bundleID = bundleID {
                favorites.append(bundleID)
            }
        }

        return favorites.isEmpty ? nil : favorites
    }

    private static func mapClipboardV1(_ json: [String: Any]) -> (items: [ClipboardItem], missing: Int) {
        guard let records = (json["builtin_package_clipboardHistory"] as? [String: Any])?["clipboardHistoryRecords"] as? [[String: Any]]
        else { return ([], 0) }

        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var items: [ClipboardItem] = []
        var missing = 0
        for record in records {
            let createdAt = parseDate(record["createdAt"] as? String, using: dateParser) ?? Date()
            let sourceBundleID = sourceBundleID(from: record["applicationPath"] as? String)
            let category = record["category"] as? String

            switch category {
            case "text", "link":
                if let text = record["text"] as? String, !text.isEmpty {
                    items.append(ClipboardItem(
                        id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: createdAt,
                        sourceBundleID: sourceBundleID))
                }
            case "image", "file":
                if let path = record["filePath"] as? String {
                    guard FileManager.default.fileExists(atPath: path) else {
                        missing += 1
                        continue
                    }
                    items.append(ClipboardItem(
                        id: UUID(), kind: .image, text: nil, imagePath: path, createdAt: createdAt,
                        sourceBundleID: sourceBundleID))
                }
            default:
                if let text = record["text"] as? String, !text.isEmpty {
                    items.append(ClipboardItem(
                        id: UUID(), kind: .text, text: text, imagePath: nil, createdAt: createdAt,
                        sourceBundleID: sourceBundleID))
                }
            }
        }
        return (items, missing)
    }

    // MARK: - v2 mappers

    private static func parseV2(_ json: [String: Any]) -> Result {
        var backup = SettingsBackup()
        backup.settings = mapSettingsV2(json)
        backup.hotkeys = mapHotkeysV2(json)
        backup.favoriteApps = mapFavoritesV2(json)
        let (clipboard, missing) = mapClipboardV2(json)
        return Result(backup: backup, clipboard: clipboard, missingImages: missing)
    }

    /// Raycast `general.hyperKeyCode` → Tinycast physical key; unknown or absent values are skipped, and no value ever maps to `.none` (an export without a Hyper key must not disable one the user already configured).
    private static let hyperKeyCodes: [String: HyperKeyPhysicalKey] = [
        "caps_lock": .capsLock,
        "right_control": .rightControl,
        "right_shift": .rightShift,
        "right_option": .rightOption,
        "right_command": .rightCommand,
    ]

    private static func mapSettingsV2(_ json: [String: Any]) -> SettingsBackup.SettingsData? {
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
        // Without the physical Hyper key the imported ⌃⌥⇧⌘ shortcuts exist but can't be triggered from it.
        if let code = general?["hyperKeyCode"] as? String, let key = hyperKeyCodes[code] {
            data.hyperKey = key.rawValue
            mapped = true
        }
        if let display = general?["hyperKeyDisplayShortcut"] as? Bool {
            data.hyperKeyReplacesGlyph = display
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
        // Exact-match only: a Raycast timeout outside Tinycast's option set is skipped, not clamped.
        if let secs = general?["popToRootTimeout"] as? Int,
            let timeout = PopToRootTimeout(rawValue: secs)
        {
            data.popToRootSeconds = timeout.rawValue
            mapped = true
        }
        // Raycast's window mode is a string ("compact"/"advanced"/...); Tinycast only has the compact toggle.
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

    /// Raycast stores the palette hotkey under `general.globalHotkey` and per-command hotkeys (clipboard, emoji, app launchers) under `commands[].macosHotkey`, all in the same `kind.shortcut` shape. Raycast uses the same Carbon keycodes and modifier names Tinycast does, so `LayoutIndependent` shortcuts map directly; character-based (`LayoutDependent`) ones are skipped since Tinycast keys on keycodes. Hyper Key shortcuts need no special-casing: Raycast exports them expanded into the four explicit modifiers, and the physical key itself comes over via `hyperKeyCode` in `mapSettingsV2`.
    private static func mapHotkeysV2(_ json: [String: Any]) -> SettingsBackup.HotkeyBackup? {
        let settings = json["settings"] as? [String: Any]
        var hotkeys = SettingsBackup.HotkeyBackup()
        var apps: [String: KeyShortcut] = [:]
        var mapped = false

        if let general = settings?["general"] as? [String: Any],
            let shortcut = keyShortcutV2(from: general["globalHotkey"])
        {
            hotkeys.togglePalette = shortcut
            mapped = true
        }

        for command in settings?["commands"] as? [[String: Any]] ?? [] {
            guard let shortcut = keyShortcutV2(from: command["macosHotkey"]) else { continue }
            switch command["extensionId"] as? String {
            case "e:r:clipboard-history":
                hotkeys.toggleClipboard = shortcut
                mapped = true
            case "e:r:emoji-picker":
                hotkeys.toggleEmoji = shortcut
                mapped = true
            case "e:r:applications":
                if let path = appPath(fromCommandID: command["id"] as? String),
                    let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
                {
                    apps[bundleID] = shortcut
                    mapped = true
                }
            default:
                break
            }
        }
        if !apps.isEmpty { hotkeys.apps = apps }
        return mapped ? hotkeys : nil
    }

    /// Build a `KeyShortcut` from a Raycast v2 hotkey object (`{ kind: { shortcut: { modifiers, key } } }`).
    private static func keyShortcutV2(from hotkey: Any?) -> KeyShortcut? {
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
        return KeyShortcut(
            carbonKeyCode: code, carbonModifiers: KeyShortcut.carbonModifiers(from: flags))
    }

    /// Raycast marks favorited items with `favoriteOrder` (0-based). Only app favorites map to Tinycast, keyed by bundle ID (the same key `FavoritesStore` uses), preserving Raycast's order.
    private static func mapFavoritesV2(_ json: [String: Any]) -> [String]? {
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

    /// The launched app's path is the tail of an applications command id: `c:r:applications::*::application::=::/Applications/Ghostty.app`.
    private static func appPath(fromCommandID id: String?) -> String? {
        guard let id, let range = id.range(of: "::=::") else { return nil }
        let path = String(id[range.upperBound...])
        return path.isEmpty ? nil : path
    }

    // MARK: - Clipboard (shared parsing helper)

    private static func mapClipboardV2(_ json: [String: Any]) -> (items: [ClipboardItem], missing: Int) {
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

    /// Raycast stores the emoji skin tone under an emoji command's preferences; a recursive search avoids hard-coding a brittle path. Enum raw values line up (`light`…`dark`); Raycast's `default` maps to none.
    private static func mapSkinTone(_ json: [String: Any]) -> String? {
        guard let raw = firstValue(forKey: "skinTone", in: json) as? String else { return nil }
        if raw == "default" { return EmojiSkinTone.none.rawValue }
        return EmojiSkinTone(rawValue: raw)?.rawValue
    }

    private static func sourceBundleID(from path: String?) -> String? {
        guard let path = path else { return nil }
        return Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
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
