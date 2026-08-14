import Foundation

/// Decodes the rate feeds into one snapshot. Pure, so the harness covers it; the store does the IO.
enum CurrencyFeed {
    /// Fiat quotes are keyed `<base><code>` and omit the base's own row.
    private struct FiatPayload: Decodable {
        let success: Bool
        let source: String
        let quotes: [String: Double]
    }

    /// Crypto is quoted the other way round — one unit costs this much of `target`.
    private struct CryptoPayload: Decodable {
        let success: Bool
        let target: String
        let rates: [String: Double]
    }

    /// One units-per-base table from both feeds; `complete` is false when the coins didn't land.
    static func snapshot(
        fiat: Data, crypto: Data?, now: Date
    ) throws -> (rates: CurrencyRates, complete: Bool) {
        let payload = try JSONDecoder().decode(FiatPayload.self, from: fiat)
        let base = payload.source
        guard payload.success, base.count == 3 else { throw URLError(.cannotParseResponse) }

        var rates: [String: Double] = [:]
        rates.reserveCapacity(payload.quotes.count + 1)
        for (pair, rate) in payload.quotes where usable(rate) {
            guard pair.count == 6, pair.hasPrefix(base) else { continue }
            rates[String(pair.dropFirst(3))] = rate
        }
        guard !rates.isEmpty else { throw URLError(.cannotParseResponse) }
        rates[base] = 1

        var coins = 0
        // Last, so the coin feed's own price wins for a symbol the fiat table also quotes.
        if let crypto, let payload = try? JSONDecoder().decode(CryptoPayload.self, from: crypto),
            payload.success, payload.target == base
        {
            for (code, price) in payload.rates where usable(price) && usable(1 / price) {
                rates[code] = 1 / price
                coins += 1
            }
        }

        return (CurrencyRates(base: base, rates: rates, fetchedAt: now), coins > 0)
    }

    /// Only whole snapshots are persisted, so a cached one pricing no coin predates them entirely.
    static func pricesCoins(_ snapshot: CurrencyRates) -> Bool {
        CalcCurrency.cryptoCodes.contains { snapshot.rates[$0] != nil }
    }

    private static func usable(_ rate: Double) -> Bool {
        rate > 0 && rate.isFinite
    }
}
