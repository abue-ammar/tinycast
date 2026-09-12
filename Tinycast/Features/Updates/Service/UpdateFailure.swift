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
            return "The download did not finish. \(detail)"
        case .extractFailed(let detail):
            return "The downloaded archive could not be expanded. \(detail)"
        case .noAppInArchive:
            return "The downloaded archive does not contain Tinycast."
        case .quarantined:
            return "macOS quarantined the downloaded app and Tinycast could not clear the flag."
        case .bundleMismatch:
            return "The downloaded app is not this build of Tinycast."
        case .identityMismatch:
            return "The downloaded app is not signed by the identity this copy was signed with."
        case .versionMismatch(let expected, let found):
            return "The downloaded app is version \(found), not \(expected)."
        case .replaceFailed(let detail):
            return "Tinycast could not be replaced. \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .identityMismatch, .bundleMismatch, .versionMismatch:
            return "Nothing was installed. Download the release from GitHub instead, so you can "
                + "check it yourself."
        case .replaceFailed:
            return "Nothing was installed. This usually means /Applications is not writable by "
                + "your account."
        case .quarantined:
            return "Nothing was installed."
        default:
            return nil
        }
    }
}
