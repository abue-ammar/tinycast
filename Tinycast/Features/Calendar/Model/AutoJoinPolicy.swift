import Foundation

/// Whether a meeting should open itself, and which one — the card's pick among what it may join.
struct AutoJoinPolicy: Sendable {
    /// Only a meeting starting at or after this instant qualifies, so arming mid-call is inert.
    let armedAt: Date
    let namedProvidersOnly: Bool

    func meeting(
        from events: [MeetingEvent], now: Date, window: UpcomingWindow,
        joined: Set<MeetingEvent.ID>
    ) -> MeetingEvent? {
        // Filtered before the pick, so a skipped link cannot shadow a call starting beside it.
        let candidates =
            namedProvidersOnly ? events.filter { $0.link?.provider != .generic } : events
        guard let carded = window.carded(from: candidates, now: now) else { return nil }
        // Never early, never a meeting that was already under way, never the same one twice.
        guard carded.start >= armedAt, now >= carded.start, !joined.contains(carded.id) else {
            return nil
        }
        return carded
    }
}
