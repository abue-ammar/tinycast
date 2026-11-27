import Foundation

/// When the support window may next ask. Pure: every date is handed in.
enum SupportReminderSchedule {
    static let interval: TimeInterval = 30 * 24 * 3600

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// Seconds until the next ask; `0` is due now. Anchor on the last ask, or first run if none.
    static func wait(since anchor: Date, now: Date) -> TimeInterval {
        // Clamped both ways: a clock moved backwards must not park the ask past one interval.
        let elapsed = min(max(0, now.timeIntervalSince(anchor)), interval)
        return interval - elapsed
    }

    /// Thanksgiving through Giving Tuesday, midnight US Eastern to midnight US Pacific.
    static func givingWeek(in year: Int) -> DateInterval {
        let thanksgiving = utc.date(
            from: DateComponents(year: year, month: 11, hour: 5, weekday: 5, weekdayOrdinal: 4))!
        return DateInterval(start: thanksgiving, duration: (6 * 24 + 3) * 3600)
    }

    static func isGivingWeekAskDue(since anchor: Date, now: Date) -> Bool {
        givingWeek(in: utc.component(.year, from: now)).contains(now) && wait(since: anchor, now: now) <= 0
    }
}
