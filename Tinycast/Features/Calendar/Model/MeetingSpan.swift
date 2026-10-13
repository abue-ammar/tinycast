import Foundation

/// The days Tinycast reads, today included, so the query and every sentence naming it agree.
enum MeetingSpan: Int, CaseIterable, Identifiable, Sendable {
    case today = 1
    case todayAndTomorrow = 2
    case nextSevenDays = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .todayAndTomorrow: return "Today and Tomorrow"
        case .nextSevenDays: return "Next 7 Days"
        }
    }

    /// Midnight today through midnight at the end of the span, in the calendar's own zone.
    func interval(from now: Date, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.dateInterval(of: .day, for: now)?.start,
            let end = calendar.date(byAdding: .day, value: rawValue, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    var possessivePhrase: String {
        switch self {
        case .today: return "today's"
        case .todayAndTomorrow: return "today's and tomorrow's"
        case .nextSevenDays: return "the next 7 days'"
        }
    }

    /// "today or tomorrow", for a sentence where "and" would read wrong.
    var orPhrase: String {
        switch self {
        case .today: return "today"
        case .todayAndTomorrow: return "today or tomorrow"
        case .nextSevenDays: return "in the next 7 days"
        }
    }
}
