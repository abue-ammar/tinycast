import Foundation

struct HyperKeyDiagnostics: Codable, Equatable, Sendable {
    struct ConflictingApp: Codable, Equatable, Sendable {
        let name: String
        let severity: HyperKeyConflictPolicy.Severity
    }

    struct Takeover: Codable, Equatable, Sendable {
        let keyboards: [String]
        let likelyApps: [String]
    }

    struct KeyboardTap: Codable, Equatable, Sendable {
        let appName: String
        let isSlow: Bool
    }

    struct SecureInput: Codable, Equatable, Sendable {
        let reportedOwner: String?
        let ownerIsLoginWindow: Bool
        let likelyOwners: [String]
    }

    let isActive: Bool
    let activeKeyTitle: String?
    /// Nil while there is no tap to ask.
    let eventTapEnabled: Bool?
    let runLoopSourceValid: Bool?
    let remappedKeyboards: [String]
    let conflictingApps: [ConflictingApp]
    let karabinerVirtualKeyboards: [String]
    let karabinerConflict: Bool
    let capsLockMappingConflicts: [String]
    let takeover: Takeover?
    let keyboardTaps: [KeyboardTap]
    let secureInputCompatibilityActive: Bool
    /// Nil while Secure Input is off.
    let secureInput: SecureInput?
}
