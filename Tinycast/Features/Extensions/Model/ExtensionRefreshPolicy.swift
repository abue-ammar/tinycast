import Foundation

/// Raycast's background refresh, reduced to decisions. No state, no clock reads: every moment arrives
/// as a parameter, so the harness drives it.
enum ExtensionRefreshPolicy {
    /// What a manifest may ask for; tighter would burn battery re-rendering a subtitle.
    static let minimumInterval: TimeInterval = 60
    /// A broken command backs off to at most this, so it can never pin the loop.
    static let maximumInterval: TimeInterval = 24 * 3600
    /// Due commands firing together run as one batch when they land inside this window.
    static let coalescingWindow: TimeInterval = 30
    /// Idle wakeups stay this rare; date math is cheap but a wakeup never is.
    static let idleHeartbeat: TimeInterval = 300

    /// `"90s"`, `"1m"`, `"12h"`, `"1d"` → seconds, clamped to the floor. Anything else is no schedule.
    static func parse(_ raw: String?) -> TimeInterval? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.count >= 2, let unit = text.last, let amount = Double(text.dropLast()),
            amount.isFinite, amount > 0
        else { return nil }
        let multiplier: Double
        switch unit {
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3600
        case "d": multiplier = 86400
        default: return nil
        }
        return max(amount * multiplier, minimumInterval)
    }

    /// Only `no-view` refreshes; a `menu-bar` interval parses but never schedules.
    static func isSchedulable(mode: ExtensionCommandMode, interval: TimeInterval?) -> Bool {
        mode == .noView && interval != nil
    }

    /// Failures back off exponentially, so a broken command stops costing a boot every minute.
    static func effectiveInterval(_ base: TimeInterval, consecutiveFailures: Int) -> TimeInterval {
        min(base * pow(2, Double(max(consecutiveFailures, 0))), maximumInterval)
    }

    /// Deterministic per-command phase, so installs don't re-fire in lockstep after sleep.
    static func jitter(entryID: String, interval: TimeInterval) -> TimeInterval {
        let bound = min(interval * 0.1, 300)
        guard bound >= 1 else { return 0 }
        return Double(stableHash(entryID) % UInt64(Int(bound)))
    }

    static func nextDue(
        lastRun: Date?, now: Date, interval: TimeInterval, consecutiveFailures: Int, entryID: String
    ) -> Date {
        guard let lastRun else { return now }
        return lastRun.addingTimeInterval(
            effectiveInterval(interval, consecutiveFailures: consecutiveFailures)
                + jitter(entryID: entryID, interval: interval))
    }

    /// A hung background run dies before its successor is due, or ticks pile up behind it.
    static func timeout(interval: TimeInterval) -> TimeInterval {
        min(max(interval, 15), 120)
    }

    /// Launcher dot for a scheduled command: an active refresh, its dimmed twin when switched
    /// off, or the last background error. Anything unschedulable shows nothing at all.
    static func indicator(
        schedulable: Bool, backgroundEnabled: Bool, lastError: String?
    ) -> ExtensionRefreshState? {
        guard schedulable else { return nil }
        if let lastError { return .failed(lastError) }
        return backgroundEnabled ? .active : .idle
    }

    /// `subtitle: null` clears back to the manifest; the stored override otherwise wins. A subtitle
    /// restating the owning extension is dropped — the row already carries it on the right.
    static func displaySubtitle(manifest: String?, override: String?, ownerTitle: String) -> String? {
        let resolved = (override ?? manifest)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolved, !resolved.isEmpty else { return nil }
        return resolved.compare(ownerTitle, options: .caseInsensitive) == .orderedSame
            ? nil : resolved
    }

    /// `String.hashValue` is seeded per launch; phase stability needs its own hash.
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in text.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return hash
    }
}
