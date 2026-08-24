import Foundation

/// Whether a meeting should open itself, and which one. It answers what the join card is already
/// showing, so the card, the chord and auto-join can never offer different meetings.
struct AutoJoinPolicy: Sendable {
    /// Only a meeting starting at or after this instant qualifies, so arming mid-call is inert.
    let armedAt: Date

    func meeting(
        from events: [MeetingEvent], now: Date, window: UpcomingWindow,
        joined: Set<MeetingEvent.ID>
    ) -> MeetingEvent? {
        guard let carded = window.carded(from: events, now: now) else { return nil }
        // Never early, never a meeting that was already under way, never the same one twice.
        guard carded.start >= armedAt, now >= carded.start, !joined.contains(carded.id) else {
            return nil
        }
        return carded
    }
}
