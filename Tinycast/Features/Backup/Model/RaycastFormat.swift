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

/// The independently importable categories in a Raycast export, so the user can pick a subset.
struct RaycastImportOptions: OptionSet, Sendable {
    let rawValue: Int
    static let shortcuts = RaycastImportOptions(rawValue: 1 << 0)
    static let favorites = RaycastImportOptions(rawValue: 1 << 1)
    static let emojiSkinTone = RaycastImportOptions(rawValue: 1 << 2)
    static let launchAtLogin = RaycastImportOptions(rawValue: 1 << 3)
    static let menuBarVisibility = RaycastImportOptions(rawValue: 1 << 4)
    static let clipboardHistory = RaycastImportOptions(rawValue: 1 << 5)
    static let popToRoot = RaycastImportOptions(rawValue: 1 << 6)
    static let compactMode = RaycastImportOptions(rawValue: 1 << 7)
    static let snippets = RaycastImportOptions(rawValue: 1 << 8)
    static let aliases = RaycastImportOptions(rawValue: 1 << 9)
    static let all: RaycastImportOptions = [
        .shortcuts, .favorites, .emojiSkinTone, .launchAtLogin, .menuBarVisibility, .clipboardHistory,
        .popToRoot, .compactMode, .snippets, .aliases
    ]
}

/// The one branch between the two readers. See docs/features/raycast-import.md.
enum RaycastFormat: Sendable, Equatable {
    /// Raycast 1.x: a bare `IV(16) ‖ AES-256-CBC(gzip(JSON), PKCS#7)` blob with no header.
    case v1
    /// Raycast X: gzip → JSON envelope → AES-256-GCM ciphertext under a scrypt key.
    case v2

    /// From the leading bytes alone, so a file is labelled before a passphrase is typed.
    static func detect(_ raw: Data) throws -> RaycastFormat {
        let magic = [UInt8](raw.prefix(3))
        if magic.count == 3, magic[0] == 0x1f, magic[1] == 0x8b, magic[2] == 0x08 { return .v2 }
        // A v1 file is whole AES blocks: a 16-byte IV plus at least one block of ciphertext.
        guard raw.count >= 32, raw.count % 16 == 0 else { throw RaycastImportError.notRaycastFile }
        return .v1
    }

    var title: String {
        switch self {
        case .v1: return "Raycast 1.x export"
        case .v2: return "Raycast X export"
        }
    }

    /// Categories the format carries; offering one it lacks would import nothing.
    var supportedOptions: RaycastImportOptions {
        switch self {
        case .v1: return RaycastImportOptions.all.subtracting([.launchAtLogin, .aliases])
        case .v2: return .all
        }
    }
}
