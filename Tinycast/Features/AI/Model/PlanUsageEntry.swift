import Foundation

struct PlanUsageEntry: Equatable, Sendable {
    enum Note: Equatable, Sendable {
        case refreshFailed
        case updated(ago: TimeInterval)
    }

    /// Three missed polls; fresher numbers need no date beside them.
    static let staleAfter: TimeInterval = 15 * 60

    var usage: PlanUsage?
    var updatedAt: Date?
    var isRefreshing = false
    var failed = false

    func note(at now: Date) -> Note? {
        guard usage != nil, let updatedAt else { return nil }
        if failed { return .refreshFailed }
        let age = now.timeIntervalSince(updatedAt)
        return age >= Self.staleAfter ? .updated(ago: age) : nil
    }
}
