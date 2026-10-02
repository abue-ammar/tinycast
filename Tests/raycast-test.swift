import CryptoKit
import Foundation

// The RAYCFG3 container and clipboard mapping, including import-time retention.
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
        recognition()
        decryption()
        gunzipSlices()
        gunzipCap()
        clipboardMapping()
        clipboardPinMetadata()
        clipboardRetention()

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

    static let passphrase = "12345678"

    /// Built in-process, so no real export is committed; the one scrypt derive is shared.
    static let fixture: (file: Data, payloadStart: Int, futureSchema: Data)? = {
        let salt = Data(repeating: 0x22, count: 16)
        let iv = Data(repeating: 0x33, count: 16)
        let key = SymmetricKey(
            data: Scrypt.derive(
                passphrase: Array(passphrase.utf8), salt: [UInt8](salt),
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

    // MARK: - Recognition

    static func recognition() {
        expect(
            RaycastDecoder.isExport(Data("RAYCFG3\n".utf8)),
            "the container signature is recognised before its body is read")
        expect(!RaycastDecoder.isExport(Data()), "empty data is not an export")
        expect(
            !RaycastDecoder.isExport(Data(repeating: 0xa5, count: 512)),
            "an unsigned blob is not an export")
        expect(
            !RaycastDecoder.isExport(Data("RAYCFG3".utf8)),
            "the signature includes its trailing newline")
    }

    // MARK: - Decrypt

    static func decryption() {
        guard let fixture else {
            failures += 1
            print("FAIL: fixture encryption")
            return
        }
        let file = fixture.file

        expect(
            (try? RaycastDecoder.decrypt(file, passphrase: passphrase)) == plainJSON,
            "the container decrypts its length-prefixed gzip header and tagged payload")
        expectThrows("wrong passphrase", .incorrectPassphrase) {
            try RaycastDecoder.decrypt(file, passphrase: "wrong-passphrase")
        }

        // A slice keeps the caller's indices, which the offsets inside the decoder must not assume.
        let padded = Data(repeating: 0x00, count: 7) + file
        expect(
            (try? RaycastDecoder.decrypt(padded.dropFirst(7), passphrase: passphrase)) == plainJSON,
            "a non-zero-based slice decrypts the same as the whole file")

        // Everything below is rejected before the key derivation, so none of it pays scrypt's cost.
        expectThrows("without the container signature", .notRaycastFile) {
            try RaycastDecoder.decrypt(file.dropFirst(), passphrase: passphrase)
        }
        expectThrows("shorter than the fixed header", .corrupt) {
            try RaycastDecoder.decrypt(file.prefix(11), passphrase: passphrase)
        }
        expectThrows("unknown container schema", .corrupt) {
            try RaycastDecoder.decrypt(fixture.futureSchema, passphrase: passphrase)
        }

        // Every truncation short of the payload, so no offset can run off an end.
        var misclassified: [Int] = []
        for cut in 0..<fixture.payloadStart {
            let expected: RaycastImportError = cut < 8 ? .notRaycastFile : .corrupt
            do {
                _ = try RaycastDecoder.decrypt(file.prefix(cut), passphrase: "")
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
            if (try? RaycastDecoder.decrypt(damaged, passphrase: "")) != nil {
                lengthsRead.append(value)
            }
        }
        expect(lengthsRead.isEmpty, "an out-of-range header length is rejected: \(lengthsRead)")
    }

    // MARK: - Clipboard

    static func clipboardEntry(
        _ text: String, createdAt: String = "2001-01-01T00:00:00.123Z", pinned: Any? = nil
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "createdAt": createdAt,
            "items": [["representations": [["mimeType": "text/plain", "content": text]]]]
        ]
        entry["pinned"] = pinned
        return entry
    }

    static func clipboardImport(
        _ entries: [[String: Any]], existingImages: Set<String> = []
    ) -> (items: [ClipboardItem], missing: Int) {
        let json: [String: Any] = ["clipboardEntries": entries]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
            let decoded = try? JSONSerialization.jsonObject(with: data)
        else {
            expect(false, "the synthetic clipboard fixture serializes")
            return ([], 0)
        }
        return RaycastClipboardImport.parse(
            decoded, now: { Date(timeIntervalSince1970: 1_700_000_000) },
            fileExists: { existingImages.contains($0) })
    }

    static func clipboardMapping() {
        var text = clipboardEntry("unused", pinned: true)
        text["items"] = [[
            "representations": [
                ["mimeType": "text/html", "content": "<b>rich text</b>"],
                ["mimeType": "text/plain;charset=utf-8", "content": "plain text"],
                ["mimeType": "image/png", "contentType": "url", "content": "/synthetic/text.png"]
            ]
        ]]
        let image: [String: Any] = [
            "createdAt": "2001-01-02T00:00:00Z", "pinned": true,
            "items": [["representations": [
                ["mimeType": "image/png", "contentType": "url", "content": "/synthetic/pin.png"]
            ]]]
        ]
        var missingImage = image
        missingImage["items"] = [["representations": [
            ["mimeType": "image/png", "contentType": "url", "content": "/synthetic/missing.png"]
        ]]]
        var unpinnedMissingImage = missingImage
        unpinnedMissingImage["pinned"] = false
        let result = clipboardImport(
            [text, clipboardEntry("ordinary", pinned: false), image, missingImage, unpinnedMissingImage],
            existingImages: ["/synthetic/pin.png"])
        expect(result.items.count == 3, "text and existing images import; missing images do not")
        expect(result.missing == 2, "missing images count equally with and without a pin")
        guard result.items.count == 3 else { return }
        let clip = result.items[0]
        expect(clip.kind == .text && clip.text == "plain text", "text/plain still wins over rich text and images")
        expect(clip.imagePath == nil && clip.sourceBundleID == nil, "text paths and source stay unchanged")
        expect(
            abs(clip.createdAt.timeIntervalSince1970 - 978_307_200.123) < 0.000_001,
            "fractional createdAt is preserved")
        expect(clip.isPinned && clip.pinnedAt == clip.createdAt, "a Boolean pin uses the original creation date")
        expect(!result.items[1].isPinned, "an explicit false stays unpinned")
        let imageClip = result.items[2]
        expect(imageClip.kind == .image && imageClip.text == nil, "image kind and text stay unchanged")
        expect(imageClip.imagePath == "/synthetic/pin.png", "the original image path is preserved")
        expect(imageClip.sourceBundleID == nil, "an imported image still has no source bundle ID")
        expect(imageClip.createdAt == Date(timeIntervalSince1970: 978_393_600), "whole-second dates still parse")
        expect(imageClip.isPinned && imageClip.pinnedAt == imageClip.createdAt, "image pins are preserved")

        var emptyTextImage = image
        emptyTextImage["items"] = [["representations": [
            ["mimeType": "text/plain", "content": ""],
            ["mimeType": "image/png", "contentType": "url", "content": "/synthetic/pin.png"]
        ]]]
        expect(
            clipboardImport([emptyTextImage], existingImages: ["/synthetic/pin.png"]).items.first?.kind == .image,
            "empty text still falls through to an image")
    }

    static func clipboardPinMetadata() {
        let malformed: [Any?] = [nil, NSNull(), "true", "false", 0, 1, 42, 1.0, [], ["pinned": true]]
        for (index, value) in malformed.enumerated() {
            let result = clipboardImport([clipboardEntry("malformed \(index)", pinned: value)])
            expect(result.items.count == 1, "malformed or missing pin \(index) does not discard the text")
            expect(result.items.first?.isPinned == false, "malformed or missing pin \(index) stays unpinned")
        }
        for date in ["invalid", ""] {
            let clip = clipboardImport([clipboardEntry("fallback", createdAt: date, pinned: true)]).items.first
            expect(clip?.createdAt == Date(timeIntervalSince1970: 1_700_000_000), "bad dates still use the clock")
            expect(clip?.isPinned == true && clip?.pinnedAt == clip?.createdAt, "a pin uses the fallback date too")
        }
        var absentDate = clipboardEntry("absent date", pinned: true)
        absentDate.removeValue(forKey: "createdAt")
        let clip = clipboardImport([absentDate]).items.first
        expect(clip?.isPinned == true && clip?.pinnedAt == clip?.createdAt, "missing createdAt still preserves a pin")
        let empty = RaycastClipboardImport.parse(nil, now: Date.init, fileExists: { _ in false })
        expect(empty.items.isEmpty && empty.missing == 0, "missing clipboard history stays empty")
    }

    static func clipboardRetention() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("raycast-clipboard-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let imported = clipboardImport([
            clipboardEntry("later pin", createdAt: "2001-01-02T00:00:00Z", pinned: true),
            clipboardEntry("earlier pin", pinned: true),
            clipboardEntry("expired ordinary", pinned: false),
            clipboardEntry("recent ordinary", createdAt: Date().ISO8601Format(), pinned: false),
            [
                "createdAt": "2001-01-03T00:00:00Z", "pinned": true,
                "items": [["representations": [
                    ["mimeType": "image/png", "contentType": "url", "content": "/synthetic/retained.png"]
                ]]]
            ]
        ], existingImages: ["/synthetic/retained.png"])
        let store = ClipboardStore(directory: root)
        expect(store.maxAge == ClipboardRetention.threeMonths.maxAge, "the default retention remains three months")
        expect(store.importEntries(imported.items) == 5, "all mapped candidates reach the real store")
        expect(
            store.search("", filter: .all).compactMap(\.text) == ["earlier pin", "later pin", "recent ordinary"],
            "old pins survive immediate pruning in deterministic date order; old unpinned text does not")
        store.enforceLimits()
        expect(store.items.filter(\.isPinned).count == 3, "subsequent retention also keeps text and image pins")
        store.close()
        let reopened = ClipboardStore(directory: root)
        reopened.load()
        expect(
            reopened.search("", filter: .all).compactMap(\.text) == ["earlier pin", "later pin", "recent ordinary"],
            "pins and pruning persist in SQLite across a reload")
        expect(
            reopened.items.filter(\.isPinned).allSatisfy { $0.pinnedAt == $0.createdAt },
            "the original pin metadata is persisted, not just held in the import array")
        expect(
            reopened.items.contains { $0.isPinned && $0.imagePath == "/synthetic/retained.png" },
            "an old pinned image survives import-time retention and reload too")
    }

    // MARK: - Zlib

    static func gunzipSlices() {
        // `decompress` indexes a zero-based copy, so a slice must not be re-indexed.
        var prefixed = Data(repeating: 0xa5, count: 32)
        prefixed.append(gzippedJSON)
        expect(
            (try? Zlib.gunzip(prefixed.dropFirst(32))) == plainJSON,
            "a non-zero-index gzip slice decompresses instead of trapping")
        expect((try? Zlib.gunzip(gzippedJSON)) == plainJSON, "a zero-based gzip still works")
        expect((try? Zlib.gunzip(Data(repeating: 0x00, count: 32))) == nil, "non-gzip throws")
    }

    /// Built here, never committed: a fixture past the default cap cannot live in the repo.
    static func gunzipCap() {
        let oversized = Data(repeating: 0x5a, count: 70 * 1024 * 1024)
        guard let gzipped = try? Zlib.gzip(oversized) else {
            failures += 1
            print("FAIL: the oversized fixture did not gzip")
            return
        }
        do {
            _ = try Zlib.gunzip(gzipped)
            failures += 1
            print("FAIL: a 70 MB payload passed the 64 MB default cap")
        } catch ZlibError.tooLarge {
            passes += 1
        } catch {
            failures += 1
            print("FAIL: the default cap threw \(error), expected tooLarge")
        }
        expect(
            (try? Zlib.gunzip(gzipped, maxOutput: 512 * 1024 * 1024))?.count == oversized.count,
            "the same payload inflates under the 512 MB payload cap")
    }
}
