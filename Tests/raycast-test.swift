import CommonCrypto
import CryptoKit
import Foundation

// Format detection, the v1 AES-256-CBC decrypt, the v2 RAYCFG3 container and the JSON → RaycastV1Payload mapping. No real export is used: the crypto cases build a synthetic fixture in-process and the mapping cases hand `payload(_:)` hand-written JSON. Turning payload values into Tinycast's own types lives in `RaycastImportV1` and `RaycastImportV2`, which need AppKit and are covered by the app build. Scrypt costs seconds per derive here, so `v2Fixture` derives once and only the cases that must reach key derivation do.
@main
@MainActor
enum RaycastTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expectThrows(
        _ message: String, _ expected: RaycastImportError? = nil,
        _ body: () throws -> some Any
    ) {
        do {
            _ = try body()
            failures += 1
            print("FAIL: \(message) — did not throw")
        } catch let error as RaycastImportError {
            guard let expected, error != expected else {
                passes += 1
                return
            }
            failures += 1
            print("FAIL: \(message) — threw \(error), expected \(expected)")
        } catch {
            passes += 1
        }
    }

    static func main() {
        detection()
        decryption()
        v2Decryption()
        hotkeyParsing()
        preferenceMapping()
        clipboardMapping()
        favoritesAndSnippets()
        gunzipSlices()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Fixtures

    /// gzip of `{"raycast_version":"1.104.24"}`, produced with mtime 0 so the bytes are stable.
    static let gzippedJSON = Data([
        0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0xab, 0x56,
        0x2a, 0x4a, 0xac, 0x4c, 0x4e, 0x2c, 0x2e, 0x89, 0x2f, 0x4b, 0x2d, 0x2a,
        0xce, 0xcc, 0xcf, 0x53, 0xb2, 0x52, 0x32, 0xd4, 0x33, 0x34, 0x30, 0xd1,
        0x33, 0x32, 0x51, 0xaa, 0x05, 0x00, 0x6f, 0xf1, 0x55, 0x48, 0x1e, 0x00,
        0x00, 0x00
    ])
    static let plainJSON = Data(#"{"raycast_version":"1.104.24"}"#.utf8)

    /// Builds a v1 file the way Raycast does: a random IV, then AES-256-CBC under a key that is one SHA-256 of the passphrase.
    static func makeV1File(_ plaintext: Data, passphrase: String, iv: Data? = nil) -> Data {
        let iv = iv ?? Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = Data(SHA256.hash(data: Data(passphrase.utf8)))
        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        let capacity = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { out in
            plaintext.withUnsafeBytes { input in
                iv.withUnsafeBytes { iv in
                    key.withUnsafeBytes { key in
                        CCCrypt(
                            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            key.baseAddress, key.count, iv.baseAddress,
                            input.baseAddress, input.count,
                            out.baseAddress, capacity, &moved)
                    }
                }
            }
        }
        precondition(status == kCCSuccess, "fixture encryption failed")
        return iv + output.prefix(moved)
    }

    static func payload(_ json: String) -> RaycastV1Payload? {
        try? RaycastV1Decoder.payload(Data(json.utf8))
    }

    // MARK: - Detection

    static func detection() {
        expect(
            (try? RaycastFormat.detect(makeV1File(gzippedJSON, passphrase: "pw"))) == .v1,
            "a headerless block-aligned blob is v1")
        expect(
            (try? RaycastFormat.detect(Data("RAYCFG3\n".utf8))) == .v2,
            "the v2 container signature wins before its body is read")

        expectThrows("empty data", .notRaycastFile) { try RaycastFormat.detect(Data()) }
        expectThrows("one byte", .notRaycastFile) { try RaycastFormat.detect(Data([0x00])) }
        expectThrows("17 bytes", .notRaycastFile) {
            try RaycastFormat.detect(Data(repeating: 0xa5, count: 17))
        }
        expectThrows("IV only", .notRaycastFile) {
            try RaycastFormat.detect(Data(repeating: 0xa5, count: 16))
        }
        expectThrows("misaligned", .notRaycastFile) {
            try RaycastFormat.detect(Data(repeating: 0xa5, count: 100))
        }
        expect(
            (try? RaycastFormat.detect(Data(repeating: 0xa5, count: 32))) == .v1,
            "the smallest legal v1 file is IV + one block")

        // Block-aligned and signed: routing must not silently retry a broken v2 file as v1.
        let alignedContainer = Data("RAYCFG3\n".utf8) + Data(repeating: 0xa5, count: 24)
        expect(
            (try? RaycastFormat.detect(alignedContainer)) == .v2,
            "the container signature wins over the v1 size rules")

        expect(RaycastFormat.v2.supportedOptions == .all, "v2 carries every category")
        expect(
            !RaycastFormat.v1.supportedOptions.contains(.launchAtLogin),
            "v1 exports no launch-at-login preference")
        expect(
            !RaycastFormat.v1.supportedOptions.contains(.aliases),
            "v1 exports no aliases")
        expect(
            RaycastFormat.v1.supportedOptions.contains(.shortcuts),
            "v1 still carries app and command hotkeys")
    }

    // MARK: - V2 decrypt

    static let v2Passphrase = "12345678"

    /// A `RAYCFG3` container around `gzippedJSON`, so no real export is ever committed. Scrypt is
    /// deliberately slow and this harness is unoptimized, so the one derive here is shared by all.
    static let v2Fixture: (file: Data, payloadStart: Int, futureSchema: Data)? = {
        let salt = Data(repeating: 0x22, count: 16)
        let iv = Data(repeating: 0x33, count: 16)
        let key = SymmetricKey(
            data: Scrypt.derive(
                passphrase: Array(v2Passphrase.utf8), salt: [UInt8](salt),
                n: 16384, r: 8, p: 1, dkLen: 32))
        func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
        func container(schemaVersion: Int, sealed: AES.GCM.SealedBox) -> Data? {
            let header: [String: Any] = [
                "appVersion": "2.0.5.0",
                "schemaVersion": schemaVersion,
                "encryption": ["iv": hex(iv), "salt": hex(salt)]
            ]
            guard let headerJSON = try? JSONSerialization.data(withJSONObject: header),
                let compressedHeader = try? Zlib.gzip(headerJSON)
            else { return nil }
            var file = Data("RAYCFG3\n".utf8)
            let length = UInt32(compressedHeader.count)
            file.append(contentsOf: [
                UInt8(length & 0xff), UInt8((length >> 8) & 0xff),
                UInt8((length >> 16) & 0xff), UInt8(length >> 24)
            ])
            file.append(compressedHeader)
            file.append(sealed.ciphertext)
            file.append(sealed.tag)
            return file
        }
        guard let nonce = try? AES.GCM.Nonce(data: iv),
            let sealed = try? AES.GCM.seal(gzippedJSON, using: key, nonce: nonce),
            let file = container(schemaVersion: 3, sealed: sealed),
            let futureSchema = container(schemaVersion: 4, sealed: sealed)
        else { return nil }
        return (file, file.count - sealed.ciphertext.count - 16, futureSchema)
    }()

    static func v2Decryption() {
        guard let fixture = v2Fixture else {
            failures += 1
            print("FAIL: v2 fixture encryption")
            return
        }
        let file = fixture.file

        expect(
            (try? RaycastV2Decoder.decrypt(file, passphrase: v2Passphrase)) == plainJSON,
            "the container decrypts its length-prefixed gzip header and tagged payload")
        expectThrows("v2 wrong passphrase", .incorrectPassphrase) {
            try RaycastV2Decoder.decrypt(file, passphrase: "wrong-passphrase")
        }

        // A slice keeps the caller's indices, which the offsets inside the decoder must not assume.
        let padded = Data(repeating: 0x00, count: 7) + file
        expect(
            (try? RaycastV2Decoder.decrypt(padded.dropFirst(7), passphrase: v2Passphrase))
                == plainJSON,
            "a non-zero-based slice decrypts the same as the whole file")

        // Everything below is rejected before the key derivation, so none of it pays scrypt's cost.
        expectThrows("v2 without the container signature", .notRaycastFile) {
            try RaycastV2Decoder.decrypt(file.dropFirst(), passphrase: v2Passphrase)
        }
        expectThrows("v2 shorter than the fixed header", .corrupt) {
            try RaycastV2Decoder.decrypt(file.prefix(11), passphrase: v2Passphrase)
        }
        // Raycast's own schema number, which is not our v1/v2 split, gates the reader.
        expectThrows("v2 unknown container schema", .corrupt) {
            try RaycastV2Decoder.decrypt(fixture.futureSchema, passphrase: v2Passphrase)
        }

        // Every truncation short of the payload, so no offset inside the decoder can run off an end.
        var misclassified: [Int] = []
        for cut in 0..<fixture.payloadStart {
            let expected: RaycastImportError = cut < 8 ? .notRaycastFile : .corrupt
            do {
                _ = try RaycastV2Decoder.decrypt(file.prefix(cut), passphrase: "")
                misclassified.append(cut)
            } catch {
                if (error as? RaycastImportError) != expected { misclassified.append(cut) }
            }
        }
        expect(misclassified.isEmpty, "a truncated container is rejected, not read: \(misclassified)")

        var lengthsRead: [UInt32] = []
        for value: UInt32 in [0, 1, 0x0010_0001, 0xffff_ffff] {
            var damaged = file
            damaged[8] = UInt8(value & 0xff)
            damaged[9] = UInt8((value >> 8) & 0xff)
            damaged[10] = UInt8((value >> 16) & 0xff)
            damaged[11] = UInt8(value >> 24)
            if (try? RaycastV2Decoder.decrypt(damaged, passphrase: "")) != nil {
                lengthsRead.append(value)
            }
        }
        expect(lengthsRead.isEmpty, "an out-of-range header length is rejected: \(lengthsRead)")
    }

    // MARK: - Decrypt

    static func decryption() {
        let file = makeV1File(gzippedJSON, passphrase: "12345678")
        let decrypted = try? RaycastV1Decoder.decrypt(file, passphrase: "12345678")
        expect(decrypted == plainJSON, "round trip returns the original JSON")

        // The IV is the file's first block, not a value derived from the passphrase.
        let fixedIV = Data(repeating: 0x11, count: 16)
        let pinned = makeV1File(gzippedJSON, passphrase: "12345678", iv: fixedIV)
        expect(
            (try? RaycastV1Decoder.decrypt(pinned, passphrase: "12345678")) == plainJSON,
            "decrypt reads the IV from the file")

        expectThrows("wrong passphrase", .incorrectPassphrase) {
            try RaycastV1Decoder.decrypt(file, passphrase: "wrong")
        }
        // Plaintext that unpads cleanly but isn't gzip is a wrong key, not a corrupt file.
        expectThrows("decrypts but isn't gzip", .incorrectPassphrase) {
            try RaycastV1Decoder.decrypt(
                makeV1File(Data(repeating: 0x41, count: 64), passphrase: "pw"), passphrase: "pw")
        }
        expectThrows("truncated ciphertext", .notRaycastFile) {
            try RaycastV1Decoder.decrypt(Data(file.prefix(24)), passphrase: "12345678")
        }
        expectThrows("empty file", .notRaycastFile) {
            try RaycastV1Decoder.decrypt(Data(), passphrase: "12345678")
        }
        // Damaging the first ciphertext block is deterministic: the gzip header it decrypts to no longer matches.
        var damaged = pinned
        damaged[20] ^= 0xff
        expectThrows("corrupted ciphertext", .incorrectPassphrase) {
            try RaycastV1Decoder.decrypt(damaged, passphrase: "12345678")
        }

        expectThrows("payload of non-JSON", .corrupt) {
            try RaycastV1Decoder.payload(Data("not json".utf8))
        }
        expectThrows("payload of a JSON array", .corrupt) {
            try RaycastV1Decoder.payload(Data("[1,2,3]".utf8))
        }
        expect(payload("{}") != nil, "an empty object yields an empty payload")
    }

    // MARK: - Hotkey strings

    static func hotkeyParsing() {
        // Carbon masks: cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096.
        let single = RaycastV1Decoder.hotkey(from: "Command-32")
        expect(single?.carbonKeyCode == 32, "trailing component is the key code")
        expect(single?.carbonModifiers == 256, "Command maps to cmdKey")

        let hyper = RaycastV1Decoder.hotkey(from: "Shift-Control-Option-Command-32")
        expect(hyper?.carbonModifiers == 256 | 512 | 2048 | 4096, "all four modifiers combine")

        expect(
            RaycastV1Decoder.hotkey(from: "command-49")?.carbonModifiers == 256,
            "modifier names are case-insensitive")
        expect(RaycastV1Decoder.hotkey(from: "122")?.carbonModifiers == 0, "a bare key code is valid")
        expect(RaycastV1Decoder.hotkey(from: nil) == nil, "no hotkey")
        expect(RaycastV1Decoder.hotkey(from: "") == nil, "empty string")
        expect(RaycastV1Decoder.hotkey(from: "Command-") == nil, "missing key code")
        expect(RaycastV1Decoder.hotkey(from: "Command-Space") == nil, "non-numeric key code")
        // Dropping an unknown modifier would import a weaker combo that could shadow something else.
        expect(RaycastV1Decoder.hotkey(from: "Fn-Command-32") == nil, "unknown modifier rejects")
    }

    // MARK: - Preferences

    static func preferenceMapping() {
        let json = """
            {
              "raycast_version": "1.104.24",
              "builtin_package_raycastPreferences": {
                "preferencesAdvanced": {
                  "popToRootTimeout": 90,
                  "emojiSkinTone": "medium",
                  "raycast_hyperKey_state": {
                    "enabled": true, "keyCode": 57, "includeShiftKey": true
                  }
                },
                "preferencesAppearance": {
                  "raycastPreferredWindowMode": "compact",
                  "showFavoritesInCompactMode": true,
                  "statusBarIsVisible": false
                }
              },
              "builtin_package_rootSearch": {
                "rootSearch": [
                  { "key": "org.alacritty", "type": "systemApp",
                    "path": "/Applications/Alacritty.app", "hotkey": "Command-32" },
                  { "key": "net.freemacsoft.AppCleaner", "type": "systemApp",
                    "hotkey": "Shift-Control-Option-Command-32" },
                  { "key": "builtin_command_clipboardHistory", "type": "command",
                    "hotkey": "Control-9" },
                  { "key": "builtin_command_emojiSymbols", "type": "command",
                    "hotkey": "Control-49" },
                  { "key": "builtin_command_configurationExport", "type": "command" },
                  { "key": "com.example.NoHotkey", "type": "systemApp" }
                ]
              }
            }
            """
        guard let parsed = payload(json) else {
            failures += 1
            print("FAIL: preference fixture did not parse")
            return
        }

        expect(parsed.popToRootTimeout == 90, "popToRootTimeout")
        expect(parsed.emojiSkinTone == "medium", "emojiSkinTone")
        expect(parsed.hyperKey?.enabled == true, "hyper key enabled")
        expect(parsed.hyperKey?.keyCode == 57, "hyper key is a Carbon code, not a name")
        expect(parsed.hyperKey?.includesShift == true, "hyper key includes shift")
        expect(parsed.windowMode == "compact", "window mode")
        expect(parsed.showFavoritesInCompactMode == true, "favorites in compact mode")
        expect(parsed.statusBarIsVisible == false, "menu-bar visibility")

        // `key` is already the bundle ID, so no app has to still be installed.
        expect(parsed.appHotkeys.count == 2, "only entries with a hotkey become app shortcuts")
        expect(parsed.appHotkeys["org.alacritty"]?.carbonKeyCode == 32, "app hotkey key code")
        expect(
            parsed.appHotkeys["net.freemacsoft.AppCleaner"]?.carbonModifiers == 6912,
            "app hotkey modifiers")
        expect(parsed.toggleClipboard?.carbonKeyCode == 9, "clipboard command hotkey")
        expect(parsed.toggleEmoji?.carbonKeyCode == 49, "emoji command hotkey")

        // A v1 export has no global palette hotkey and no launch-at-login flag to find.
        let empty = payload(
            """
            {"builtin_package_raycastPreferences": {"preferencesGeneral": {
                "raycastAlternativeEscape": false}}}
            """)
        expect(empty?.popToRootTimeout == nil, "absent preferences stay nil")
        expect(empty?.hyperKey == nil, "absent hyper key stays nil")
        expect(empty?.appHotkeys.isEmpty == true, "no rootSearch means no hotkeys")

        // Wrong-typed values must be ignored, not crash or coerce.
        let wrongTypes = payload(
            """
            {"builtin_package_raycastPreferences": {"preferencesAdvanced": {
                "popToRootTimeout": "90", "emojiSkinTone": 3,
                "raycast_hyperKey_state": {"enabled": true}}}}
            """)
        expect(wrongTypes?.popToRootTimeout == nil, "a string timeout is ignored")
        expect(wrongTypes?.emojiSkinTone == nil, "a numeric skin tone is ignored")
        expect(wrongTypes?.hyperKey == nil, "a hyper key without a key code is ignored")

        let disabledHyper = payload(
            """
            {"builtin_package_raycastPreferences": {"preferencesAdvanced": {
                "raycast_hyperKey_state": {"enabled": false, "keyCode": 57}}}}
            """)
        expect(disabledHyper?.hyperKey?.enabled == false, "a disabled hyper key is reported as such")
    }

    // MARK: - Clipboard

    static func clipboardMapping() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "raycast-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("clip.png")
        FileManager.default.createFile(atPath: image.path, contents: Data([0x89, 0x50]))

        let json = """
            {
              "builtin_package_clipboardHistory": {
                "clipboardHistoryDisabledApplications": ["com.apple.keychainaccess"],
                "clipboardHistoryRecords": [
                  { "category": "text", "text": "hello",
                    "createdAt": "2026-08-01T19:52:03Z",
                    "applicationPath": "/System/Applications/Calculator.app" },
                  { "category": "link", "text": "https://example.com",
                    "createdAt": "2026-08-01T19:53:34.250Z" },
                  { "category": "image", "text": "Image (214x90)",
                    "filePath": "\(image.path)", "createdAt": "2026-08-01T19:52:14Z" },
                  { "category": "image", "text": "Image (10x10)",
                    "filePath": "/nope/gone.png", "createdAt": "2026-08-01T19:52:15Z" },
                  { "category": "text", "text": "", "createdAt": "2026-08-01T19:52:16Z" },
                  { "category": "file", "text": "report.pdf", "filePath": "/nope/report.pdf",
                    "createdAt": "2026-08-01T19:52:17Z" },
                  { "text": "no category here", "createdAt": "2026-08-01T19:52:18Z" }
                ]
              }
            }
            """
        guard let parsed = payload(json) else {
            failures += 1
            print("FAIL: clipboard fixture did not parse")
            return
        }

        expect(
            parsed.clipboardDisabledApps == ["com.apple.keychainaccess"],
            "per-app clipboard exclusions")
        // text + link + existing image + file label + uncategorised; empty text and the missing image drop out.
        expect(parsed.clipboard.count == 5, "records that carry content are imported")
        expect(parsed.missingImages == 1, "an image whose file is gone is counted, not imported")
        expect(parsed.clipboard.filter { $0.kind == .image }.count == 1, "only `image` becomes a clip")
        expect(
            parsed.clipboard.contains { $0.text == "report.pdf" },
            "a file record imports its label as text")
        expect(
            parsed.clipboard.contains { $0.text == "no category here" },
            "a record with no category falls back to text")
        expect(
            !parsed.clipboard.contains { $0.text?.isEmpty == true },
            "empty text is skipped")

        // v1 stamps whole seconds; v2's fractional form must still parse.
        let plain = parsed.clipboard.first { $0.text == "hello" }
        expect(
            plain?.createdAt == Date(timeIntervalSince1970: 1_785_613_923),
            "whole-second timestamps parse")
        expect(
            parsed.clipboard.first { $0.text == "https://example.com" }?.createdAt
                == Date(timeIntervalSince1970: 1_785_614_014.25),
            "fractional-second timestamps parse")
        expect(
            plain?.sourceBundleID == "com.apple.calculator",
            "applicationPath resolves to a bundle ID")
        expect(
            parsed.clipboard.first { $0.text == "https://example.com" }?.sourceBundleID == nil,
            "a record with no applicationPath has no source")

        expect(payload("{}")?.clipboard.isEmpty == true, "no clipboard provider means no clips")
    }

    // MARK: - Favorites and snippets

    static func favoritesAndSnippets() {
        let favorites = payload(
            """
            {"builtin_package_navigation": {"pinnedMenuItems": [
                {"key": "org.alacritty"},
                "com.apple.Safari",
                {"path": "/System/Applications/Calculator.app"},
                {"key": "builtin_command_clipboardHistory"},
                "not a bundle id",
                {"nothing": true}
            ]}}
            """)
        expect(
            favorites?.favorites == ["org.alacritty", "com.apple.Safari", "com.apple.calculator"],
            "app favorites keep their order; commands and junk are dropped")
        expect(payload("{}")?.favorites.isEmpty == true, "no navigation provider means no favorites")

        let snippets = payload(
            """
            {"builtin_package_snippets": {"snippets": [
                {"name": "Sig", "text": "Best,\\nAB", "keyword": ";sig"},
                {"name": "  Padded  ", "text": "x", "keyword": "   "},
                {"name": "   ", "text": "no name"},
                {"name": "No text"}
            ]}}
            """)
        expect(snippets?.snippets.count == 2, "unnamed and text-less snippets are dropped")
        expect(snippets?.snippets.first?.keyword == ";sig", "keyword carries over")
        expect(snippets?.snippets.last?.name == "Padded", "names are trimmed")
        expect(snippets?.snippets.last?.keyword == nil, "a blank keyword becomes nil")
    }

    // MARK: - Zlib

    static func gunzipSlices() {
        // `decompress` indexes a zero-based copy, so a slice starting elsewhere must not be re-indexed.
        var prefixed = Data(repeating: 0xa5, count: 32)
        prefixed.append(gzippedJSON)
        expect(
            (try? Zlib.gunzip(prefixed.dropFirst(32))) == plainJSON,
            "a non-zero-index gzip slice decompresses instead of trapping")
        expect((try? Zlib.gunzip(gzippedJSON)) == plainJSON, "a zero-based gzip still works")
        expect((try? Zlib.gunzip(Data(repeating: 0x00, count: 32))) == nil, "non-gzip throws")
    }
}
