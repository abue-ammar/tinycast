import Foundation

/// Everything an update can fail at, phrased for the window that reports it.
enum UpdateFailure: LocalizedError, Equatable {
    case downloadFailed(String)
    case extractFailed(String)
    case noAppInArchive
    case quarantined
    case bundleMismatch
    case identityMismatch
    case versionMismatch(expected: String, found: String)
    case replaceFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let detail):
            return String(localized: "The download did not finish. \(detail)", bundle: .appLanguage)
        case .extractFailed(let detail):
            return String(localized: "The downloaded archive could not be expanded. \(detail)", bundle: .appLanguage)
        case .noAppInArchive:
            return String(localized: "The downloaded archive does not contain Tinycast.", bundle: .appLanguage)
        case .quarantined:
            return String(
                localized: "macOS quarantined the downloaded app and Tinycast could not clear the flag.",
                bundle: .appLanguage)
        case .bundleMismatch:
            return String(localized: "The downloaded app is not this build of Tinycast.", bundle: .appLanguage)
        case .identityMismatch:
            return String(
                localized: "The downloaded app is not signed by the identity this copy was signed with.",
                bundle: .appLanguage)
        case .versionMismatch(let expected, let found):
            return String(localized: "The downloaded app is version \(found), not \(expected).", bundle: .appLanguage)
        case .replaceFailed(let detail):
            return String(localized: "Tinycast could not be replaced. \(detail)", bundle: .appLanguage)
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .identityMismatch, .bundleMismatch, .versionMismatch:
            return String(
                localized:
                    "Nothing was installed. Download the release from GitHub instead, so you can check it yourself.",
                bundle: .appLanguage
            )
        case .replaceFailed:
            return String(
                localized: "Nothing was installed. This usually means /Applications is not writable by your account.",
                bundle: .appLanguage)
        case .quarantined:
            return String(localized: "Nothing was installed.", bundle: .appLanguage)
        default:
            return nil
        }
    }
}
