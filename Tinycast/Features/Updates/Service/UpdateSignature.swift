import CryptoKit
import Foundation

/// Tinycast's own Ed25519 release key: the trust that survives a change of signing identity.
enum UpdateSignature {
    private static let publicKeyInfoKey = "TinycastUpdatePublicKey"

    /// `signature` is a release's `.sig` asset: the base64 signature of its zip.
    static func isSigned(_ archive: URL, by signature: Data) -> Bool {
        guard let key = bundledKey,
            let data = try? Data(contentsOf: archive, options: .mappedIfSafe)
        else { return false }
        return isSigned(data, by: signature, key: key)
    }

    static func isSigned(_ data: Data, by signature: Data, key: Curve25519.Signing.PublicKey) -> Bool {
        let encoded = String(decoding: signature, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: encoded) else { return false }
        return key.isValidSignature(raw, for: data)
    }

    private static var bundledKey: Curve25519.Signing.PublicKey? {
        guard let encoded = Bundle.main.object(forInfoDictionaryKey: publicKeyInfoKey) as? String,
            let raw = Data(base64Encoded: encoded)
        else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }
}
