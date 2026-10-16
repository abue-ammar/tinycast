import Foundation

enum RaycastImportError: LocalizedError {
    case notRaycastFile
    case incorrectPassphrase
    case corrupt
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .notRaycastFile:
            return String(localized: "This doesn't look like a Raycast export (.rayconfig).")
        case .incorrectPassphrase:
            return String(localized: "Incorrect passphrase, or the file is corrupted.")
        case .corrupt: return String(localized: "The Raycast export could not be read.")
        case .tooLarge:
            return String(
                localized: """
                    This export is too large to import. Clear some Raycast clipboard history and \
                    export again.
                    """)
        }
    }
}
