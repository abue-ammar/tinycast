import Foundation

/// How far ahead Tinycast reads, so the query's length and every sentence naming it agree.
enum MeetingSpan: Sendable {
    case today
    case todayAndTomorrow

    init(includesTomorrow: Bool) {
        self = includesTomorrow ? .todayAndTomorrow : .today
    }

    /// Midnight today through midnight at the end of the span, in the calendar's own zone.
    func interval(from now: Date, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.dateInterval(of: .day, for: now)?.start,
            let end = calendar.date(byAdding: .day, value: days, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// "today's and tomorrow's", for a sentence naming the events that are read.
    var possessivePhrase: String {
        switch self {
        case .today: return "today's"
        case .todayAndTomorrow: return "today's and tomorrow's"
        }
    }

    /// "today or tomorrow", for a sentence saying nothing falls in the span, where "and" reads wrong.
    var orPhrase: String {
        switch self {
        case .today: return "today"
        case .todayAndTomorrow: return "today or tomorrow"
        }
    }

    private var days: Int {
        switch self {
        case .today: return 1
        case .todayAndTomorrow: return 2
        }
    }
}
