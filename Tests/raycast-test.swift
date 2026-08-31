import CryptoKit
import Foundation

// The RAYCFG3 container: recognition, framing and the AES-256-GCM decrypt.
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
}
