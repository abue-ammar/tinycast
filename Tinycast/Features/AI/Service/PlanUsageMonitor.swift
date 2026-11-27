import AppKit
import Observation

@MainActor
@Observable
final class PlanUsageMonitor {
    private static let interval: Duration = .seconds(180)
    private static let minimumGap: Duration = .seconds(30)

    private struct Read {
        let task: Task<Void, Never>
        var refreshAgain = false
    }

    private(set) var entries: [PlanUsage.Provider: PlanUsageEntry] = [:]

    @ObservationIgnored var providers: @MainActor () -> [PlanUsage.Provider] = { [] }
    @ObservationIgnored var reader: @MainActor (PlanUsage.Provider) async -> PlanUsage.Reading = { _ in
        .failed
    }
    @ObservationIgnored var onChange: (@MainActor (PlanUsage.Provider, PlanUsage?, PlanUsage) -> Void)?

    @ObservationIgnored private(set) var isRunning = false
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var reads: [PlanUsage.Provider: Read] = [:]
    @ObservationIgnored private var lastRead: [PlanUsage.Provider: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var latestResult: [PlanUsage.Provider: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var sleepObservers: [NotificationToken] = []

    var usage: [PlanUsage.Provider: PlanUsage] { entries.compactMapValues(\.usage) }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeSleep()
    }

    func stop() {
        isRunning = false
        isAsleep = false
        poll?.cancel()
        poll = nil
        for read in reads.values { read.task.cancel() }
        reads = [:]
        lastRead = [:]
        latestResult = [:]
        sleepObservers = []
        entries = [:]
    }

    func refresh(force: Bool = false) {
        guard isRunning, !isAsleep else { return }
        let current = providers()
        for provider in lastRead.keys where !current.contains(provider) { drop(provider) }
        for provider in current { read(provider, force: force) }
        schedulePoll()
    }

    func refresh(_ provider: PlanUsage.Provider, force: Bool = false) {
        guard isRunning, !isAsleep, providers().contains(provider) else { return }
        read(provider, force: force)
    }

    func apply(
        _ usage: PlanUsage, for provider: PlanUsage.Provider, startedAt: ContinuousClock.Instant
    ) {
        guard isRunning, providers().contains(provider), isCurrent(provider, since: startedAt)
        else { return }
        lastRead[provider] = .now
        store(usage, for: provider, startedAt: startedAt)
    }

    private func read(_ provider: PlanUsage.Provider, force: Bool) {
        if reads[provider] != nil {
            if force { reads[provider]?.refreshAgain = true }
            return
        }
        let startedAt = ContinuousClock.now
        if !force, let last = lastRead[provider], last.duration(to: startedAt) < Self.minimumGap {
            return
        }
        lastRead[provider] = startedAt
        entries[provider, default: PlanUsageEntry()].isRefreshing = true
        let reader = reader
        let task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let reading = await reader(provider)
            guard !Task.isCancelled else { return }
            self?.finish(provider, with: reading, startedAt: startedAt)
        }
        reads[provider] = Read(task: task)
    }

    private func finish(
        _ provider: PlanUsage.Provider, with reading: PlanUsage.Reading,
        startedAt: ContinuousClock.Instant
    ) {
        guard let read = reads.removeValue(forKey: provider) else { return }
        guard providers().contains(provider) else {
            drop(provider)
            return
        }
        if read.refreshAgain, !isAsleep {
            self.read(provider, force: true)
            return
        }
        guard !isAsleep, isCurrent(provider, since: startedAt) else {
            entries[provider]?.isRefreshing = false
            return
        }
        switch reading {
        case .usage(let usage):
            store(usage, for: provider, startedAt: startedAt)
        case .unavailable:
            latestResult[provider] = startedAt
            entries[provider] = nil
        case .failed:
            entries[provider]?.isRefreshing = false
            entries[provider]?.failed = true
        }
    }

    private func isCurrent(
        _ provider: PlanUsage.Provider, since startedAt: ContinuousClock.Instant
    )
        -> Bool
    {
        if let latest = latestResult[provider] { return startedAt >= latest }
        return true
    }

    private func store(
        _ usage: PlanUsage, for provider: PlanUsage.Provider, startedAt: ContinuousClock.Instant
    ) {
        latestResult[provider] = startedAt
        let previous = entries[provider]?.usage
        entries[provider] = PlanUsageEntry(
            usage: usage, updatedAt: Date(), isRefreshing: reads[provider] != nil)
        onChange?(provider, previous, usage)
    }

    private func drop(_ provider: PlanUsage.Provider) {
        reads.removeValue(forKey: provider)?.task.cancel()
        lastRead[provider] = nil
        latestResult[provider] = nil
        entries[provider] = nil
    }

    private func schedulePoll() {
        poll?.cancel()
        poll = Task { [weak self] in
            try? await Task.sleep(for: Self.interval)
            guard !Task.isCancelled else { return }
            self?.refresh(force: true)
        }
    }

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        let sleep = center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
        let wake = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }
        sleepObservers = [
            NotificationToken(sleep, center: center), NotificationToken(wake, center: center)
        ]
    }

    private func pause() {
        isAsleep = true
        poll?.cancel()
    }

    /// Limits may have reset overnight, so waking reads at once rather than at the next tick.
    private func resume() {
        guard isAsleep else { return }
        isAsleep = false
        refresh(force: true)
    }
}
