import Foundation

/// The days Tinycast reads, today included, so the query and every sentence naming it agree.
enum MeetingSpan: Int, CaseIterable, Identifiable, Sendable {
    case today = 1
    case todayAndTomorrow = 2
    case nextSevenDays = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .todayAndTomorrow: return String(localized: "Today and Tomorrow")
        case .nextSevenDays: return String(localized: "Next 7 Days")
        }
    }

    /// Midnight today through midnight at the end of the span, in the calendar's own zone.
    func interval(from now: Date, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.dateInterval(of: .day, for: now)?.start,
            let end = calendar.date(byAdding: .day, value: rawValue, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    var nothingScheduledMessage: String {
        switch self {
        case .today: return String(localized: "Nothing scheduled today")
        case .todayAndTomorrow: return String(localized: "Nothing scheduled today or tomorrow")
        case .nextSevenDays: return String(localized: "Nothing scheduled in the next 7 days")
        }
    }
}
