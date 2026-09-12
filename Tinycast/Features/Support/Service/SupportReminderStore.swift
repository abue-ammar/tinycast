import Foundation

/// The support reminder's clock: it decides when to ask, and never presents anything itself.
@MainActor
final class SupportReminderStore {
    /// Keeps the first evaluation, and any window it raises, clear of the login rush.
    private static let startupDelay = Duration.seconds(60)
    /// A due-but-withheld ask comes back this often, rather than waiting out another interval.
    private static let retryInterval: TimeInterval = 600
    /// Switched off, the only thing left to wait for is the switch, so the pump idles instead.
    private static let idleInterval: TimeInterval = 3600

    var onDue: (@MainActor () -> Void)?

    private let settings: AppSettings
    private let fileURL: URL
    private var state: State
    private var pump: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        fileURL = AppPaths.applicationSupport().appendingPathComponent("support-reminder.json")
        if let data = try? Data(contentsOf: fileURL),
            let stored = try? JSONDecoder().decode(State.self, from: data)
        {
            state = stored
        } else {
            state = State(firstSeenAt: Date())
            persist()
        }
    }

    deinit { pump?.cancel() }

    func start() {
        // Replace rather than bail: an exited loop leaves a non-nil task that would block restart.
        pump?.cancel()
        pump = Task { [weak self] in
            try? await Task.sleep(for: Self.startupDelay)
            while !Task.isCancelled {
                // Optional-chained: the sleep must not retain the store, or nothing can release it.
                guard let wait = self?.advance() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// Called on every showing, by any route: whoever just read the pitch is not asked again soon.
    func markAsked(at now: Date = Date()) {
        state.lastAskedAt = now
        persist()
    }

    // MARK: - Private

    /// The last ask, or first run when there has been none.
    private var anchor: Date { state.lastAskedAt ?? state.firstSeenAt }

    /// One turn of the pump: offer the ask if it is due, and answer how long to wait.
    private func advance() -> TimeInterval {
        let wait = SupportReminderSchedule.wait(since: anchor, now: Date())
        guard settings.supportRemindersEnabled else { return max(wait, Self.idleInterval) }
        guard wait <= 0 else { return wait }
        onDue?()
        // Floored: a withheld ask leaves the anchor where it was, and this must not spin on it.
        return max(SupportReminderSchedule.wait(since: anchor, now: Date()), Self.retryInterval)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private struct State: Codable {
        var firstSeenAt: Date
        var lastAskedAt: Date?
    }
}
