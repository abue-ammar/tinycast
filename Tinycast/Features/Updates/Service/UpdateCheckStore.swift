import Foundation

/// The daily release check. See docs/features/updates.md.
@MainActor
@Observable
final class UpdateCheckStore {
    private nonisolated static let endpoint = URL(
        string: "https://api.github.com/repos/\(ReleaseFeed.repository)/releases?per_page=20")!
    /// Daily, measured from `lastCheckedAt`, so relaunching never re-asks GitHub.
    private static let refreshInterval: TimeInterval = 24 * 3600
    /// Shorter retry, so a machine offline at launch sees a release soon after it reconnects.
    private static let retryInterval: TimeInterval = 2 * 3600
    /// Keeps the first check clear of the login rush.
    private static let startupDelay = Duration.seconds(30)

    let channel: ReleaseChannel
    let runningVersion: AppVersion?

    /// The newest release on this channel, whether or not it is newer than what is running.
    private(set) var latest: AvailableRelease?
    private(set) var lastCheckedAt: Date?
    var isChecking: Bool { checksInFlight > 0 }

    @ObservationIgnored var onUpdateAvailable: (@MainActor (AvailableRelease) -> Void)?

    private let fileURL: URL
    @ObservationIgnored private let fetch: @Sendable () async -> Data?
    private var installedVersion: AppVersion?
    private var checksInFlight = 0
    /// At most one uninvited appearance per version per launch.
    @ObservationIgnored private var announcedVersion: AppVersion?
    @ObservationIgnored private var pump: Task<Void, Never>?

    init(
        channel: ReleaseChannel = ReleaseChannel(bundleID: Bundle.main.bundleIdentifier),
        runningVersion: AppVersion? = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(AppVersion.init),
        fileURL: URL = AppPaths.caches().appendingPathComponent("update-check.json"),
        fetch: @escaping @Sendable () async -> Data? = UpdateCheckStore.body
    ) {
        self.channel = channel
        self.runningVersion = runningVersion
        self.fileURL = fileURL
        self.fetch = fetch
        guard let data = try? Data(contentsOf: fileURL),
            let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else { return }
        latest = cache.latest
        lastCheckedAt = cache.lastCheckedAt
        installedVersion = cache.installedVersion
    }

    deinit { pump?.cancel() }

    /// Newer than what is running.
    var update: AvailableRelease? {
        guard let runningVersion else { return nil }
        return ReleaseFeed.offer(latest, running: runningVersion)
    }

    func start(after delay: Duration = UpdateCheckStore.startupDelay) {
        guard channel.updatesItself, runningVersion != nil else { return }
        // Replace rather than bail: an exited loop leaves a non-nil task that would block restart.
        stop()
        pump = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                // Optional-chained: the sleep must not retain the store, or nothing can release it.
                guard let wait = await self?.advance() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
    }

    /// The manual path: ignores freshness, and reports whether GitHub actually answered.
    @discardableResult
    func check() async -> Bool {
        guard channel.updatesItself else { return false }
        checksInFlight += 1
        defer { checksInFlight -= 1 }
        guard let data = await fetch(), !Task.isCancelled else { return false }
        latest = ReleaseFeed.newest(from: data, channel: channel, architecture: .current)
        lastCheckedAt = Date()
        persist()
        return true
    }

    func recordInstall(of version: AppVersion) {
        installedVersion = version
        persist()
    }

    enum InstallReport: Equatable {
        case installed(AppVersion)
        case notInstalled(AppVersion)
    }

    /// Taken once. A newer version running came from elsewhere, so it reports nothing.
    func takeInstallReport() -> InstallReport? {
        guard let installed = installedVersion else { return nil }
        installedVersion = nil
        persist()
        guard let runningVersion else { return nil }
        if installed == runningVersion { return .installed(installed) }
        return installed > runningVersion ? .notInstalled(installed) : nil
    }

    private func advance() async -> TimeInterval {
        // Clamped, so a future-stamped check can't park the loop past one interval.
        let age = max(0, lastCheckedAt.map { Date().timeIntervalSince($0) } ?? .infinity)
        var wait = Self.refreshInterval - age
        if wait <= 0 {
            wait = await check() ? Self.refreshInterval : Self.retryInterval
        }
        announce()
        return wait
    }

    private func announce() {
        guard !Task.isCancelled, let release = update, announcedVersion != release.version
        else { return }
        announcedVersion = release.version
        onUpdateAvailable?(release)
    }

    private func persist() {
        let cache = Cache(
            lastCheckedAt: lastCheckedAt, latest: latest, installedVersion: installedVersion)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private struct Cache: Codable {
        var lastCheckedAt: Date?
        var latest: AvailableRelease?
        var installedVersion: AppVersion?
    }

    /// Cacheless, never `URLSession.shared`, so the snapshot on disk stays the only copy.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private nonisolated static func body() async -> Data? {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        // GitHub rejects an API request carrying no User-Agent outright.
        request.setValue("Tinycast", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return data
    }
}
