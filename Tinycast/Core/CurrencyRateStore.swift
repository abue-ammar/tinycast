import Foundation

/// Downloads, caches and periodically refreshes the exchange-rate table the calculator's currency
/// conversions run on. Network and disk live here, never in `Core/Calculator/`: the engine is handed
/// a finished `CurrencySource`, which is what keeps it Foundation-only and pure.
///
/// This reaches the network, so it is gated on explicit consent — off until the user enables currency
/// conversion in Settings. Every path that could reach the network or surface a rate re-checks
/// `isEnabled` rather than trusting a caller.
@MainActor
final class CurrencyRateStore: ObservableObject {
    /// Frankfurter (`frankfurter.dev`) — open-source, no key, no account, no quota, rates blended from
    /// 84 central banks. Unfiltered: `CurrencyData.generated.swift` is generated from this same feed's
    /// currency list, so every quote it returns is one the calculator can answer for (~1.4 KB gzipped).
    static let provider = "Frankfurter"
    static let providerURL = URL(string: "https://frankfurter.dev")!
    private nonisolated static let endpoint = URL(
        string: "https://api.frankfurter.dev/v2/rates?base=USD")!
    static let refreshInterval: TimeInterval = 6 * 3600
    /// Shorter retry so a machine that was offline at launch picks rates up soon after it reconnects.
    private static let retryInterval: TimeInterval = 15 * 60

    /// Explicit user consent, persisted under the bundle-scoped defaults. Deliberately *not* part of
    /// `AppSettings`: `SettingsBackup` mirrors that type field-for-field, and an imported config —
    /// or a Raycast import — must never be able to silently grant network access.
    @Published private(set) var isEnabled: Bool

    /// The newest snapshot, or nil when none has landed — and always nil while consent is withheld.
    @Published private(set) var rates: CurrencyRates?

    private static let consentKey = "currencyRatesEnabled"
    private let defaults = UserDefaults.standard
    private let fileURL: URL
    private var pump: Task<Void, Never>?

    init() {
        // Absent reads as false, which is the only safe default for a network feature.
        isEnabled = defaults.bool(forKey: Self.consentKey)
        let bundleID = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("currency-rates.json")

        // Guard 1 — a disabled feature doesn't even read back a snapshot left on disk.
        guard isEnabled, let data = try? Data(contentsOf: fileURL) else { return }
        rates = try? JSONDecoder().decode(CurrencyRates.self, from: data)
    }

    /// What the calculator is allowed to use. Guard 2 — the read path: without consent the engine is
    /// handed `.off`, so a currency query produces no card rather than an error about missing rates.
    var source: CurrencySource { isEnabled ? .on(rates) : .off }

    /// Starts the refresh loop: fetch whenever the cached snapshot is older than `refreshInterval`,
    /// otherwise sleep exactly until it expires. A failed fetch keeps the stale snapshot and retries
    /// sooner. Guard 3 — no consent, no loop, so `AppCore.start()` can call this unconditionally.
    func start() {
        guard isEnabled, pump == nil else { return }
        pump = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isEnabled else { return }
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

    /// The Settings toggle's only entry point, called after the user accepts the consent dialog.
    /// Disabling tears the loop down, drops the snapshot and deletes the cached file — opting out
    /// shouldn't leave downloaded data behind.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
        if enabled {
            start()
        } else {
            pump?.cancel()
            pump = nil
            rates = nil
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Manual "Update Now" from Settings; a no-op without consent.
    func refreshNow() async {
        guard isEnabled else { return }
        await fetchAndStore()
    }

    @discardableResult
    private func fetchAndStore() async -> Bool {
        // Guard 4 — re-checked at the network boundary itself: the pump may have been sleeping when
        // the user revoked consent, and this is the last line before a request goes out.
        guard isEnabled, let fetched = try? await Self.fetch() else { return false }
        // Re-check after the await: consent can be withdrawn while the request is in flight, and a
        // late response must not resurrect the feature or write the cache back to disk.
        guard isEnabled else { return false }
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
