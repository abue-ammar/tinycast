import Foundation

/// Mirrors the FoundationModels enum, which lives in `Service/` so this stays Foundation-only.
enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady

    var isAvailable: Bool { self == .available }

    /// False only when the hardware rules it out, so System Settings has nothing to offer.
    var isSupported: Bool { self != .deviceNotEligible }

    /// `nil` while the model can run, so a caller can treat it as the whole failure condition.
    var message: String? {
        switch self {
        case .available:
            return nil
        case .deviceNotEligible:
            return String(localized: "This Mac does not support Apple Intelligence.")
        case .notEnabled:
            return String(localized: "Turn on Apple Intelligence in System Settings to chat on device.")
        // Also what a profile that switches it off reports, so the copy cannot promise a download.
        case .modelNotReady:
            return String(
                localized: "Apple Intelligence is currently unavailable. Check its status in System Settings."
            )
        }
    }
}

enum AppleIntelligence {
    /// Ours rather than a vendor's: this route names no remote model to borrow an id from.
    static let modelID = "apple-intelligence"
    static let title = "Apple Intelligence"
    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!

    /// The on-device window holds prompt and reply together, so each leaves room for the other.
    static let contextBudget = 6_000
    static let maxOutputTokens = 1_024
}

/// FoundationModels reports the whole answer so far; every other transport speaks in deltas.
struct AppleIntelligenceDelta {
    private var emitted = ""

    /// The whole snapshot when the model revised what it wrote, since no prefix survives to drop.
    mutating func delta(from snapshot: String) -> String {
        defer { emitted = snapshot }
        guard snapshot.hasPrefix(emitted) else { return snapshot }
        return String(snapshot.dropFirst(emitted.count))
    }
}
