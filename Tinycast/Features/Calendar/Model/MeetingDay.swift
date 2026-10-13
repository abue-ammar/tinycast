import Foundation

/// The day a meeting falls on, counted from today, so My Schedule and the menu bar head it alike.
struct MeetingDay: Hashable, Sendable {
    let start: Date
    /// Whole days after today; a meeting still running from before midnight is happening today.
    let offset: Int

    init(for date: Date, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        offset = max(0, calendar.dateComponents([.day], from: today, to: day).day ?? 0)
        start = offset == 0 ? today : day
    }

    func title(calendar: Calendar) -> String {
        let date = calendar.formatStyle.month(.abbreviated).day()
        switch offset {
        case 0: return "Today, \(start.formatted(date))"
        case 1: return "Tomorrow, \(start.formatted(date))"
        default: return start.formatted(date.weekday(.wide))
        }
    }
}

struct MeetingDayGroup: Identifiable, Sendable {
    let day: MeetingDay
    private(set) var meetings: [MeetingEvent]

    var id: MeetingDay { day }

    /// `agenda` is already in start order, so a change of day is where a group begins.
    static func grouping(
        _ agenda: [MeetingEvent], now: Date, calendar: Calendar
    ) -> [MeetingDayGroup] {
        var groups: [MeetingDayGroup] = []
        for meeting in agenda {
            let day = MeetingDay(for: meeting.start, now: now, calendar: calendar)
            if groups.last?.day == day {
                groups[groups.count - 1].meetings.append(meeting)
            } else {
                groups.append(MeetingDayGroup(day: day, meetings: [meeting]))
            }
        }
        return groups
    }
}

extension Calendar {
    /// This calendar's own locale and zone, so a test calendar formats exactly like a user's.
    var formatStyle: Date.FormatStyle {
        Date.FormatStyle(
            locale: locale ?? Locale(identifier: "en_US"), calendar: self, timeZone: timeZone)
    }
}
