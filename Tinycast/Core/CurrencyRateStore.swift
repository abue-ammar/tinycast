import Foundation

/// Downloads, caches and periodically refreshes the exchange-rate table the calculator's currency
/// conversions run on. Network and disk live here, never in `Core/Calculator/`: the engine is handed
/// a finished `CurrencyRates` snapshot, which is what keeps it Foundation-only and pure.
@MainActor
final class CurrencyRateStore: ObservableObject {
    /// Frankfurter (`frankfurter.dev`) — open-source, no key, no account, no quota, rates blended from
    /// 84 central banks. Unfiltered: `CurrencyData.generated.swift` is generated from this same feed's
    /// currency list, so every quote it returns is one the calculator can answer for (~1.4 KB gzipped).
    private nonisolated static let endpoint = URL(
        string: "https://api.frankfurter.dev/v2/rates?base=USD")!
    private static let refreshInterval: TimeInterval = 6 * 3600
    /// Shorter retry so a machine that was offline at launch picks rates up soon after it reconnects.
    private static let retryInterval: TimeInterval = 15 * 60

    /// The newest snapshot: restored from disk at init, replaced on every successful fetch. Nil only until the very first download succeeds.
    @Published private(set) var rates: CurrencyRates?

    private let fileURL: URL
    private var pump: Task<Void, Never>?

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("currency-rates.json")

        if let data = try? Data(contentsOf: fileURL) {
            rates = try? JSONDecoder().decode(CurrencyRates.self, from: data)
        }
    }

    /// Starts the refresh loop: fetch whenever the cached snapshot is older than `refreshInterval`, otherwise sleep exactly until it expires. A failed fetch keeps the stale snapshot in place and retries sooner.
    func start() {
        guard pump == nil else { return }
        pump = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let age = self.rates.map { Date().timeIntervalSince($0.fetchedAt) } ?? .infinity
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
        guard let fetched = try? await Self.fetch() else { return false }
        rates = fetched
        if let data = try? JSONEncoder().encode(fetched) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return true
    }

    /// Off-main by way of `URLSession`'s async API; the decoded table is a plain value, so nothing but `CurrencyRates` crosses back.
    private nonisolated static func fetch() async throws -> CurrencyRates {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Frankfurter v2 answers with one flat row per pair rather than a keyed table.
        let rows = try JSONDecoder().decode([RateRow].self, from: data)
        guard let base = rows.first?.base else { throw URLError(.cannotParseResponse) }
        var rates: [String: Double] = [:]
        rates.reserveCapacity(rows.count + 1)
        for row in rows where row.rate > 0 && row.rate.isFinite && row.base == base {
            rates[row.quote] = row.rate
        }
        guard !rates.isEmpty else { throw URLError(.cannotParseResponse) }
        rates[base] = 1

        return CurrencyRates(base: base, rates: rates, fetchedAt: Date())
    }

    private struct RateRow: Decodable {
        let base: String
        let quote: String
        let rate: Double
    }
}
