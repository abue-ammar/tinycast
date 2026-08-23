import Foundation

/// Keeps Raycast 2.x's container reader separate from Raycast X's envelope.
enum RaycastImportV3 {
    static func read(_ raw: Data, passphrase: String) throws -> RaycastImport.Result {
        let payload = try RaycastV3Decoder.decrypt(raw, passphrase: passphrase)
        return try RaycastPayloadMapper.result(from: payload, snippets: .current)
    }
}
