import Foundation

/// The cacheless exchange-rate fetcher. See docs/features/calculator.md#exchange-rates.
@MainActor
@Observable
final class CurrencyRateStore {
    private nonisolated static let fiatEndpoint = URL(
        string: "https://backend.raycast.com/api/v1/currencies")!
    /// Asked for by the app's own crypto table, so the request and the table cannot drift apart.
    private nonisolated static let cryptoEndpoint = URL(
        string: "https://backend.raycast.com/api/v1/currencies/crypto?symbols="
            + CalcCurrency.cryptoCodes.joined(separator: ","))!
    /// Daily, measured from `completedAt`, so relaunching never re-fetches a snapshot still fresh.
    private static let refreshInterval: TimeInterval = 24 * 3600
    /// Shorter retry, so a machine offline at launch picks rates up soon after it reconnects.
    private static let retryInterval: TimeInterval = 30 * 60

    /// The newest snapshot, nil until the first one lands.
    private(set) var rates: CurrencyRates?

    private let fileURL: URL
    @ObservationIgnored private var pump: Task<Void, Never>?
    /// Drives the schedule: a partial snapshot answers, but only a whole one resets the clock.
    @ObservationIgnored private var completedAt: Date?

    init() {
        fileURL = AppPaths.caches().appendingPathComponent("currency-rates.json")
        guard let data = try? Data(contentsOf: fileURL),
            let cached = try? JSONDecoder().decode(CurrencyRates.self, from: data)
        else { return }
        rates = cached
        // A cache from before coins existed still prices fiat, but has to be replaced at once.
        if CurrencyFeed.pricesCoins(cached) { completedAt = cached.fetchedAt }
    }

    func start() {
        // Replace rather than bail: an exited loop leaves a non-nil task that would block restart.
        pump?.cancel()
        pump = Task { [weak self] in
            while !Task.isCancelled, let self {
                // Clamped, so a future-stamped snapshot can't park the loop past one interval.
                let age = max(0, self.completedAt.map { Date().timeIntervalSince($0) } ?? .infinity)
                guard age >= Self.refreshInterval else {
                    try? await Task.sleep(for: .seconds(Self.refreshInterval - age))
                    continue
                }
                let ok = await self.fetchAndStore()
                try? await Task.sleep(for: .seconds(ok ? Self.refreshInterval : Self.retryInterval))
            }
        }
    }

    private func fetchAndStore() async -> Bool {
        guard let result = await Self.fetch() else { return false }
        rates = result.rates
        // Never persist a coin-less run: `pricesCoins` reads the cache as whole by definition.
        guard result.complete, let data = try? JSONEncoder().encode(result.rates) else { return false }
        completedAt = result.rates.fetchedAt
        try? data.write(to: fileURL, options: .atomic)
        return true
    }

    /// Cacheless, never `URLSession.shared`, so the snapshot on disk stays the only copy.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Off-main via `URLSession`; only the plain-value `CurrencyRates` crosses back.
    private nonisolated static func fetch() async -> (rates: CurrencyRates, complete: Bool)? {
        async let fiat = body(of: fiatEndpoint)
        async let crypto = body(of: cryptoEndpoint)
        let (fiatData, cryptoData) = await (fiat, crypto)
        guard let fiatData else { return nil }
        return try? CurrencyFeed.snapshot(fiat: fiatData, crypto: cryptoData, now: Date())
    }

    private nonisolated static func body(of url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 20)
        guard let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return nil }
        return data
    }
}
