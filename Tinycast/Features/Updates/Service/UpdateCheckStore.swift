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
    /// A withheld prompt is re-offered this often, this many times, then left to the daily check.
    private static let withheldInterval: TimeInterval = 120
    private static let withheldRetryLimit = 15
    /// Keeps the first check, and any window it raises, clear of the login rush.
    private static let startupDelay = Duration.seconds(30)

    let channel: ReleaseChannel
    let runningVersion: AppVersion?

    /// The newest release on this channel, whether or not it is newer than what is running.
    private(set) var latest: AvailableRelease?
    private(set) var lastCheckedAt: Date?
    private(set) var isChecking = false

    /// Raised on an unskipped release; `false` answers that the prompt was withheld and is owed.
    @ObservationIgnored var onUpdateAvailable: (@MainActor (AvailableRelease) -> Bool)?

    private let fileURL: URL
    private var skippedVersion: AppVersion?
    /// At most one uninvited appearance per version per launch; after that the window is the user's.
    @ObservationIgnored private var announcedVersion: AppVersion?
    @ObservationIgnored private var withheldRetries = 0
    @ObservationIgnored private var pump: Task<Void, Never>?

    init() {
        channel = ReleaseChannel(bundleID: Bundle.main.bundleIdentifier)
        runningVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(AppVersion.init)
        fileURL = AppPaths.caches().appendingPathComponent("update-check.json")
        guard let data = try? Data(contentsOf: fileURL),
            let cache = try? JSONDecoder().decode(Cache.self, from: data)
        else { return }
        latest = cache.latest
        lastCheckedAt = cache.lastCheckedAt
        skippedVersion = cache.skippedVersion
    }

    deinit { pump?.cancel() }

    /// Newer than what is running. What the window offers, including a version already skipped.
    var update: AvailableRelease? {
        guard let runningVersion else { return nil }
        return ReleaseFeed.offer(latest, running: runningVersion, skipped: nil)
    }

    /// The same, minus anything dismissed. Only this may interrupt the user.
    var unskippedUpdate: AvailableRelease? {
        guard let runningVersion else { return nil }
        return ReleaseFeed.offer(latest, running: runningVersion, skipped: skippedVersion)
    }

    func start() {
        guard channel.updatesItself, runningVersion != nil else { return }
        // Replace rather than bail: an exited loop leaves a non-nil task that would block restart.
        pump?.cancel()
        pump = Task { [weak self] in
            try? await Task.sleep(for: Self.startupDelay)
            while !Task.isCancelled {
                // Optional-chained: the sleep must not retain the store, or nothing can release it.
                guard let wait = await self?.advance() else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    /// The manual path: ignores freshness, and reports whether GitHub actually answered.
    @discardableResult
    func check() async -> Bool {
        guard channel.updatesItself, !isChecking else { return false }
        isChecking = true
        defer { isChecking = false }
        guard let data = await Self.body() else { return false }
        latest = ReleaseFeed.newest(from: data, channel: channel, architecture: .current)
        lastCheckedAt = Date()
        persist()
        return true
    }

    /// Dismissing a version is what stops it asking again; a later one still will.
    func skip(_ release: AvailableRelease) {
        skippedVersion = release.version
        persist()
    }

    /// One turn of the pump: check if due, offer what is pending, and answer how long to wait.
    private func advance() async -> TimeInterval {
        // Clamped, so a future-stamped check can't park the loop past one interval.
        let age = max(0, lastCheckedAt.map { Date().timeIntervalSince($0) } ?? .infinity)
        var wait = Self.refreshInterval - age
        if wait <= 0 {
            wait = await check() ? Self.refreshInterval : Self.retryInterval
        }
        if announce() {
            withheldRetries = 0
        } else if withheldRetries < Self.withheldRetryLimit {
            // A launch straight into the palette must not spend the day's only announcement.
            withheldRetries += 1
            wait = min(wait, Self.withheldInterval)
        }
        return wait
    }

    /// `false` only when a pending release was withheld, so the pump comes back for it.
    private func announce() -> Bool {
        guard let release = unskippedUpdate, announcedVersion != release.version else { return true }
        guard onUpdateAvailable?(release) ?? true else { return false }
        announcedVersion = release.version
        return true
    }

    private func persist() {
        let cache = Cache(
            lastCheckedAt: lastCheckedAt, latest: latest, skippedVersion: skippedVersion)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private struct Cache: Codable {
        var lastCheckedAt: Date?
        var latest: AvailableRelease?
        var skippedVersion: AppVersion?
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
