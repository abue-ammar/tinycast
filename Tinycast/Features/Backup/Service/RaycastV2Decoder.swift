import CryptoKit
import Foundation

/// Unwraps the v2 container down to its payload JSON. See docs/features/raycast-import.md.
enum RaycastV2Decoder {
    private struct Header: Decodable {
        struct Encryption: Decodable {
            let iv: String
            let salt: String
        }

        let schemaVersion: Int
        let encryption: Encryption
    }

    static func decrypt(_ raw: Data, passphrase: String) throws -> Data {
        guard raw.starts(with: RaycastFormat.v2Magic) else {
            throw RaycastImportError.notRaycastFile
        }
        // `raw` can be a slice, so every offset below is measured from its own start.
        let base = raw.startIndex
        guard raw.count >= fixedHeaderLength else { throw RaycastImportError.corrupt }
        let headerLength =
            Int(raw[base + 8]) | Int(raw[base + 9]) << 8
            | Int(raw[base + 10]) << 16 | Int(raw[base + 11]) << 24
        guard headerLength > 0, headerLength <= maximumHeaderLength,
            fixedHeaderLength + headerLength <= raw.count
        else { throw RaycastImportError.corrupt }

        let payloadStart = base + fixedHeaderLength + headerLength
        let payloadEnd = raw.endIndex - authenticationTagLength
        guard payloadEnd > payloadStart,
            let headerJSON = try? Zlib.gunzip(
                raw[(base + fixedHeaderLength)..<payloadStart], maxOutput: maximumHeaderLength),
            let header = try? JSONDecoder().decode(Header.self, from: headerJSON),
            header.schemaVersion == containerSchemaVersion,
            let iv = Data(hex: header.encryption.iv), iv.count == ivLength,
            let salt = Data(hex: header.encryption.salt), salt.count == saltLength
        else { throw RaycastImportError.corrupt }

        let key = Scrypt.derive(
            passphrase: Array(passphrase.utf8), salt: [UInt8](salt),
            n: 16384, r: 8, p: 1, dkLen: 32)
        let payloadGzip: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: try AES.GCM.Nonce(data: iv),
                ciphertext: raw[payloadStart..<payloadEnd],
                tag: raw[payloadEnd...])
            payloadGzip = try AES.GCM.open(box, using: SymmetricKey(data: key))
        } catch {
            throw RaycastImportError.incorrectPassphrase
        }

        guard let payload = try? Zlib.gunzip(payloadGzip) else {
            throw RaycastImportError.corrupt
        }
        return payload
    }

    /// Raycast's own container number, unrelated to the v1/v2 split above it.
    private static let containerSchemaVersion = 3
    private static let fixedHeaderLength = 12
    private static let maximumHeaderLength = 1024 * 1024
    private static let authenticationTagLength = 16
    private static let ivLength = 16
    private static let saltLength = 16
}

extension Data {
    /// Parses an even-length hex string; returns nil on any non-hex character.
    fileprivate init?(hex: String) {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)

        func nibble(_ char: UInt8) -> UInt8? {
            switch char {
            case 0x30...0x39: return char - 0x30
            case 0x61...0x66: return char - 0x61 + 10
            case 0x41...0x46: return char - 0x41 + 10
            default: return nil
            }
        }

        var index = 0
        while index < chars.count {
            guard let high = nibble(chars[index]), let low = nibble(chars[index + 1]) else {
                return nil
            }
            bytes.append(high << 4 | low)
            index += 2
        }
        self = Data(bytes)
    }
}
