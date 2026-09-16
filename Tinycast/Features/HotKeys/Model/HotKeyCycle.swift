import Foundation

/// Pure step logic for a chord bound to more than one app. See
/// docs/features/hotkeys.md#shared-app-chords.
struct HotKeyCycle: Sendable {
    /// How long after a press the *next* press still continues from the last target, even if the
    /// just-launched app hasn't become frontmost yet.
    static let launchGrace: TimeInterval = 2.0

    private(set) var lastTarget: String?
    private var lastPressTime: TimeInterval?

    /// `members` is the cycle's order (cycle assignment order); `frontmost` is the current
    /// frontmost bundle ID, or nil. `now` is a caller-supplied monotonic timestamp, for testing.
    mutating func next(members: [String], frontmost: String?, now: TimeInterval) -> String {
        let target = resolveTarget(members: members, frontmost: frontmost, now: now)
        lastTarget = target
        lastPressTime = now
        return target
    }

    private func resolveTarget(members: [String], frontmost: String?, now: TimeInterval) -> String {
        guard let first = members.first else { return "" }
        // The frontmost member advances to its successor, wrapping.
        if let frontmost, let index = members.firstIndex(of: frontmost) {
            return members[(index + 1) % members.count]
        }
        // Left the group recently enough that a rapid re-press should keep advancing, not repeat.
        if let lastPressTime, now - lastPressTime <= Self.launchGrace,
            let lastTarget, let index = members.firstIndex(of: lastTarget)
        {
            return members[(index + 1) % members.count]
        }
        // Otherwise: back to wherever the cycle left off, or the first member if it never ran.
        if let lastTarget, members.contains(lastTarget) { return lastTarget }
        return first
    }
}
