import Foundation

enum CloudSyncStatus: Codable, Equatable, Sendable {
    case off
    case unavailable(CloudSyncUnavailability)
    case syncing(initial: Bool)
    case upToDate(Date?)
    case offline(CloudSyncProblem, lastSynced: Date?)
    /// Another Mac wrote a newer format; nothing is rewritten until this one updates.
    case needsUpdate

    var lastSynced: Date? {
        switch self {
        case .upToDate(let date): date
        case .offline(_, let date): date
        default: nil
        }
    }
}

enum CloudSyncUnavailability: Codable, Equatable, Sendable {
    case unsignedBuild, noAccount, restricted, temporarilyUnavailable

    var message: String {
        switch self {
        case .unsignedBuild:
            String(localized: "iCloud Sync needs a signed release build of Tinycast.")
        case .noAccount:
            String(localized: "Sign in to iCloud in System Settings to use iCloud Sync.")
        case .restricted:
            String(localized: "iCloud is restricted on this Mac.")
        case .temporarilyUnavailable:
            String(localized: "iCloud isn't available right now. Sync will resume on its own.")
        }
    }
}

enum CloudSyncProblem: Codable, Equatable, Sendable {
    case network, busy, storageFull, accountNeedsAttention, other(String)

    var message: String {
        switch self {
        case .network:
            String(localized: "Can't reach iCloud. Sync resumes when you're back online.")
        case .busy:
            String(localized: "iCloud is busy. Sync will retry shortly.")
        case .storageFull:
            String(localized: "Your iCloud storage is full. Free up space to keep syncing.")
        case .accountNeedsAttention:
            String(localized: "Your iCloud account needs attention in System Settings.")
        case .other(let detail): detail
        }
    }
}

enum CloudSyncStopReason: String, Codable, Sendable {
    case removedElsewhere, dataDeleted, accountChanged

    var message: String {
        switch self {
        case .removedElsewhere:
            String(localized: "This Mac was removed from iCloud Sync on another Mac.")
        case .dataDeleted:
            String(localized: "iCloud Sync was turned off because its data in iCloud was deleted.")
        case .accountChanged:
            String(localized: "iCloud Sync was turned off because the iCloud account changed.")
        }
    }
}
