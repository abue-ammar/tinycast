import Foundation

/// Which event the menu bar carries, and for how long. Every clock read is an injected `now`.
struct MenuBarSummary: Sendable {
    let leadMinutes: Int
    /// How long past the start the event stays. Nil is "Automatically" — it goes as it starts.
    let hideAfterMinutes: Int?
    /// Only events Tinycast could actually join; the rest are appointments, not meetings.
    let linkedOnly: Bool

    /// Long enough to recognise a meeting, short enough to leave the menu bar usable.
    static let titleCap = 24

    /// The earliest event still inside its window, so one hiding hands the space to the next.
    func event(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        UpcomingWindow.agenda(from: events).first {
            (!linkedOnly || $0.link != nil) && now >= $0.start - lead && now < hidesAt($0)
        }
    }

    /// Word-boundary-blind on purpose: a hard cap is the only thing that bounds the menu bar.
    static func title(_ title: String) -> String {
        guard title.count > titleCap else { return title }
        return title.prefix(titleCap - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    private var lead: TimeInterval { TimeInterval(leadMinutes * 60) }

    /// The grace never outlives the meeting, the way the join card's own window does not.
    private func hidesAt(_ event: MeetingEvent) -> Date {
        guard let hideAfterMinutes else { return event.start }
        return min(event.start + TimeInterval(hideAfterMinutes * 60), event.end)
    }
}
