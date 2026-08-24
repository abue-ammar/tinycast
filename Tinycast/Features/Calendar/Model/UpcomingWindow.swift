import Foundation

/// Which meeting is worth showing, and whether it is time. Every clock read is an injected `now`.
struct UpcomingWindow: Sendable {
    let leadMinutes: Int

    private var lead: TimeInterval { TimeInterval(leadMinutes * 60) }

    /// The events any surface may show: timed, not declined, in start order. The one place that
    /// rule lives, so the card, the chord, the schedule and the launcher cannot drift apart.
    static func agenda(from events: [MeetingEvent]) -> [MeetingEvent] {
        events
            .filter { !$0.isAllDay && !$0.isDeclined }
            .sorted { $0.start < $1.start }
    }

    /// The card's meeting: `now` inside `[start - lead, min(start + lead, end)]`, and joinable.
    /// The grace period never outlives the meeting, so a three-minute stand-up clears at its end.
    func carded(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        Self.agenda(from: events).first {
            $0.link != nil && now >= $0.start - lead && now < min($0.start + lead, $0.end)
        }
    }

    /// The chord's meeting. It answers the card first so the shortcut always joins what is on
    /// screen, then anything running, then the next one with a link.
    func joinable(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        if let carded = carded(from: events, now: now) { return carded }
        let linked = Self.agenda(from: events).filter { $0.link != nil }
        return linked.first { $0.isInProgress(now: now) } ?? linked.first { $0.start > now }
    }

    static func countdown(to start: Date, now: Date) -> String {
        let delta = start.timeIntervalSince(now)
        if delta > 0 { return "in \(Int((delta / 60).rounded(.up))) min" }
        let elapsed = Int((-delta / 60).rounded(.down))
        return elapsed == 0 ? "now" : "\(elapsed) min ago"
    }
}
