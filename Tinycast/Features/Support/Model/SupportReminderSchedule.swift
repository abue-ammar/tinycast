import Foundation

/// When the support window may next ask. Pure: every date is handed in.
enum SupportReminderSchedule {
    static let interval: TimeInterval = 30 * 24 * 3600

    /// Seconds until the next ask; `0` is due now. Anchor on the last ask, or first run if none.
    static func wait(since anchor: Date, now: Date) -> TimeInterval {
        // Clamped both ways: a clock moved backwards must not park the ask past one interval.
        let elapsed = min(max(0, now.timeIntervalSince(anchor)), interval)
        return interval - elapsed
    }
}
