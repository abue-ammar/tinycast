import AppKit
import Observation

@MainActor
@Observable
final class PlanUsageMonitor {
    private static let interval: Duration = .seconds(300)
    private static let minimumGap: TimeInterval = 30

    private(set) var entries: [PlanUsage.Provider: PlanUsageEntry] = [:]

    @ObservationIgnored var providers: @MainActor () -> [PlanUsage.Provider] = { [] }
    @ObservationIgnored var reader: @MainActor (PlanUsage.Provider) async -> PlanUsage.Reading = { _ in
        .failed
    }
    @ObservationIgnored var onChange: (@MainActor (PlanUsage.Provider, PlanUsage?, PlanUsage) -> Void)?

    @ObservationIgnored private(set) var isRunning = false
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var reads: [PlanUsage.Provider: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastRead: [PlanUsage.Provider: Date] = [:]
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
        for read in reads.values { read.cancel() }
        reads = [:]
        lastRead = [:]
        sleepObservers = []
        entries = [:]
    }

    func refresh(force: Bool = false) {
        guard isRunning, !isAsleep else { return }
        let current = providers()
        for provider in entries.keys where !current.contains(provider) { drop(provider) }
        for provider in current { read(provider, force: force) }
        schedulePoll()
    }

    func refresh(_ provider: PlanUsage.Provider, force: Bool = false) {
        guard isRunning, !isAsleep, providers().contains(provider) else { return }
        read(provider, force: force)
    }

    func apply(_ usage: PlanUsage, for provider: PlanUsage.Provider) {
        guard isRunning, providers().contains(provider) else { return }
        lastRead[provider] = Date()
        store(usage, for: provider)
    }

    private func read(_ provider: PlanUsage.Provider, force: Bool) {
        guard reads[provider] == nil else { return }
        if !force, let last = lastRead[provider], Date().timeIntervalSince(last) < Self.minimumGap {
            return
        }
        lastRead[provider] = Date()
        entries[provider, default: PlanUsageEntry()].isRefreshing = true
        let reader = reader
        reads[provider] = Task { [weak self] in
            let reading = await reader(provider)
            guard !Task.isCancelled else { return }
            self?.finish(provider, with: reading)
        }
    }

    private func finish(_ provider: PlanUsage.Provider, with reading: PlanUsage.Reading) {
        reads[provider] = nil
        switch reading {
        case .usage(let usage):
            store(usage, for: provider)
        case .unavailable:
            entries[provider] = nil
        case .failed:
            entries[provider, default: PlanUsageEntry()].isRefreshing = false
            entries[provider]?.failed = true
        }
    }

    private func store(_ usage: PlanUsage, for provider: PlanUsage.Provider) {
        let previous = entries[provider]?.usage
        entries[provider] = PlanUsageEntry(
            usage: usage, updatedAt: Date(), isRefreshing: reads[provider] != nil)
        onChange?(provider, previous, usage)
    }

    private func drop(_ provider: PlanUsage.Provider) {
        reads.removeValue(forKey: provider)?.cancel()
        lastRead[provider] = nil
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
