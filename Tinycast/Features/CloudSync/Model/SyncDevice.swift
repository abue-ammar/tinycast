import Foundation

struct SyncDevice: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var appVersion: String
    var lastSeen: Date

    /// Rounded down, so routine launches don't rewrite the record more than hourly.
    static func seen(at date: Date) -> Date {
        Date(
            timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600
        )
    }
}
