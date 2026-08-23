import CryptoKit
import Foundation

/// Reads the v3 container without changing older Raycast readers.
enum RaycastV3Decoder {
    private struct Header: Decodable {
        struct Encryption: Decodable {
            let iv: String
            let salt: String
        }

        let schemaVersion: Int
        let encryption: Encryption?
    }

    static func decrypt(_ raw: Data, passphrase: String) throws -> Data {
        guard raw.starts(with: magic) else { throw RaycastImportError.notRaycastFile }
        guard raw.count >= fixedHeaderLength else { throw RaycastImportError.corrupt }

        let bytes = [UInt8](raw)
        let headerLength =
            Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24
        guard headerLength > 0, headerLength <= maximumHeaderLength else {
            throw RaycastImportError.corrupt
        }
        let payloadStart = fixedHeaderLength + headerLength
        guard payloadStart <= raw.count,
            let headerJSON = try? Zlib.gunzip(
                Data(bytes[fixedHeaderLength..<payloadStart]), maxOutput: maximumHeaderLength),
            let header = try? JSONDecoder().decode(Header.self, from: headerJSON),
            header.schemaVersion == 3
        else { throw RaycastImportError.corrupt }

        let payloadGzip: Data
        if let encryption = header.encryption {
            let payloadEnd = raw.count - authenticationTagLength
            guard payloadEnd > payloadStart,
                let iv = Data(hex: encryption.iv), iv.count == ivLength,
                let salt = Data(hex: encryption.salt), salt.count == saltLength
            else { throw RaycastImportError.corrupt }

            let key = Scrypt.derive(
                passphrase: Array(passphrase.utf8), salt: [UInt8](salt),
                n: 16384, r: 8, p: 1, dkLen: 32)
            do {
                let box = try AES.GCM.SealedBox(
                    nonce: try AES.GCM.Nonce(data: iv),
                    ciphertext: Data(bytes[payloadStart..<payloadEnd]),
                    tag: Data(bytes[payloadEnd..<raw.count]))
                payloadGzip = try AES.GCM.open(box, using: SymmetricKey(data: key))
            } catch {
                throw RaycastImportError.incorrectPassphrase
            }
        } else {
            guard payloadStart < raw.count else { throw RaycastImportError.corrupt }
            payloadGzip = Data(bytes[payloadStart..<raw.count])
        }

        guard let payload = try? Zlib.gunzip(payloadGzip) else {
            throw RaycastImportError.corrupt
        }
        return payload
    }

    private static let magic = Data("RAYCFG3\n".utf8)
    private static let fixedHeaderLength = 12
    private static let maximumHeaderLength = 1024 * 1024
    private static let authenticationTagLength = 16
    private static let ivLength = 16
    private static let saltLength = 16
}
