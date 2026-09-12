import Foundation

/// Publishes the current minute, and only while something is watching.
@MainActor
@Observable
final class MeetingClock {
    private(set) var now = Date()

    /// Fired after each boundary; the coordinator decides what a new minute means.
    @ObservationIgnored var onTick: (@MainActor () -> Void)?

    @ObservationIgnored private var tick: Task<Void, Never>?

    var isRunning: Bool { tick != nil }

    /// Idempotent: `applyClock` calls this per watcher, and a restart would lose alignment.
    func start() {
        guard tick == nil else { return }
        now = Date()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                // Recomputed every pass, so a sleeping Mac re-aligns on wake instead of drifting.
                try? await Task.sleep(for: .seconds(Self.secondsToNextMinute()))
                guard !Task.isCancelled, let self else { return }
                self.now = Date()
                self.onTick?()
            }
        }
    }

    func stop() {
        tick?.cancel()
        tick = nil
    }

    isolated deinit {
        tick?.cancel()
    }

    /// The reference date is itself a minute boundary, so the remainder is the offset into one.
    private static func secondsToNextMinute() -> TimeInterval {
        60 - Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
    }
}
