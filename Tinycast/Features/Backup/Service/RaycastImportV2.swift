import CryptoKit
import Foundation

/// Keeps Raycast X's envelope reader separate from shared payload mapping.
enum RaycastImportV2 {
    static func read(_ raw: Data, passphrase: String) throws -> RaycastImport.Result {
        let payload = try decrypt(raw, passphrase: passphrase)
        return try RaycastPayloadMapper.result(from: payload, snippets: .builtinPackage)
    }

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
}
