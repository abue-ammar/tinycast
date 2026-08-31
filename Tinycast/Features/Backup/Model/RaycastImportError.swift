import Foundation

enum RaycastImportError: LocalizedError {
    case notRaycastFile
    case incorrectPassphrase
    case corrupt

    var errorDescription: String? {
        switch self {
        case .notRaycastFile: return "This doesn't look like a Raycast export (.rayconfig)."
        case .incorrectPassphrase: return "Incorrect passphrase, or the file is corrupted."
        case .corrupt: return "The Raycast export could not be read."
        }
    }
}
