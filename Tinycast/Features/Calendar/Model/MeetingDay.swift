import Foundation

/// The two day buckets My Schedule groups by, mirroring the clipboard's `DateBucket`.
enum MeetingDay: Sendable {
    case today
    case tomorrow

    init?(for date: Date, now: Date, calendar: Calendar) {
        if calendar.isDate(date, inSameDayAs: now) {
            self = .today
            return
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: now),
            calendar.isDate(date, inSameDayAs: next)
        else { return nil }
        self = .tomorrow
    }

    var title: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        }
    }
}
