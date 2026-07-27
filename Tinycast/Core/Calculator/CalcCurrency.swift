import Foundation

/// One currency: the ISO 4217 code shown next to the amount and the long label used as a card badge.
struct CurrencyDef: Equatable, Sendable {
    let code: String  // "EUR"
    let name: String  // "Euro"
}

/// An exchange-rate snapshot: every rate quoted as units of that currency per 1 `base`. Downloaded and persisted by `CurrencyRateStore` and handed to `CalcEngine.evaluate` — the engine never fetches, which is what keeps `Core/Calculator/` Foundation-only and pure.
struct CurrencyRates: Codable, Equatable, Sendable {
    let base: String
    let rates: [String: Double]
    /// When this table was downloaded — drives staleness, and doubles as the memo key in `CalcMemo`.
    let fetchedAt: Date

    func rate(for code: String) -> Double? {
        if let rate = rates[code], rate > 0, rate.isFinite { return rate }
        return code == base ? 1 : nil
    }

    /// Cross-rate through the base currency.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let source = rate(for: from), let target = rate(for: to) else { return nil }
        let output = amount / source * target
        return output.isFinite ? output : nil
    }
}

/// Whether the calculator may answer currency questions at all, and with what.
///
/// `.off` is the shipped default and the *only* state that exists without explicit user consent:
/// the currency path never engages, so a currency query falls through to no card — not an error
/// explaining a feature the user never turned on. `.on(nil)` means consent was given but no
/// snapshot has landed yet, which is the state that earns the "rates unavailable" message.
enum CurrencySource: Equatable, Sendable {
    case off
    case on(CurrencyRates?)
}

enum CalcCurrency {
    enum ConversionParse: Equatable {
        case value(input: Double, from: CurrencyDef, to: CurrencyDef, output: Double)
        /// One side is a currency, the other a measurement unit — `10 usd to kg`.
        case mismatch(from: String, to: String)
        /// Both sides are currencies but the snapshot doesn't quote one of them.
        case noRate(code: String)
        /// No snapshot has ever been downloaded (first run, still offline).
        case unavailable
    }

    /// The category label used in the mismatch message, mirroring `UnitCategory.displayName`.
    static let categoryName = "Currency"

    /// Detects `expr currency (to|in|->) currency`, mirroring `CalcUnits.parseConversion`'s shape so both read the same. Runs *after* the unit path, so a query both sides of which are compatible units (`10 pounds to kg`) never reaches here. A missing amount defaults to 1, so `eur to usd` reads as `1 eur to usd`.
    static func parseConversion(_ tokens: [CalcToken], source: CurrencySource) -> ConversionParse? {
        // The consent gate, before any parsing: without it the feature does not exist.
        guard case .on(let rates) = source else { return nil }
        let tokens = amountFirst(tokens)
        guard tokens.count >= 3, CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let toName) = tokens[tokens.count - 1],
            case .ident(let fromName) = tokens[tokens.count - 3]
        else { return nil }

        // A side that is only a currency is what engages this path; a side that is neither currency nor unit is just a typo, and gets no card.
        switch (byName[fromName], byName[toName]) {
        case (nil, nil):
            return nil
        case (.some, nil):
            guard let to = CalcUnits.byName[toName] else { return nil }
            return .mismatch(from: categoryName, to: to.category.displayName)
        case (nil, .some):
            guard let from = CalcUnits.byName[fromName] else { return nil }
            return .mismatch(from: from.category.displayName, to: categoryName)
        case (let from?, let to?):
            let valueTokens = Array(tokens[0..<(tokens.count - 3)])
            let input: Double
            if valueTokens.isEmpty {
                input = 1
            } else if let value = CalcParser.evaluate(valueTokens) {
                input = value
            } else {
                return nil
            }

            guard let rates else { return .unavailable }
            guard rates.rate(for: from.code) != nil else { return .noRate(code: from.code) }
            guard rates.rate(for: to.code) != nil else { return .noRate(code: to.code) }
            guard let output = rates.convert(input, from: from.code, to: to.code) else {
                return .noRate(code: to.code)
            }
            return .value(input: input, from: from, to: to, output: output)
        }
    }

    /// Money is written sign-first (`€20`), so a leading currency ident followed by its amount is swapped back into the `amount currency …` order every parser here expects.
    private static func amountFirst(_ tokens: [CalcToken]) -> [CalcToken] {
        guard tokens.count >= 2, case .ident(let name) = tokens[0], byName[name] != nil,
            case .number = tokens[1]
        else { return tokens }
        var reordered = tokens
        reordered.swapAt(0, 1)
        return reordered
    }

    /// The only currency data still written by hand: nouns several currencies share, where CLDR
    /// correctly refuses to choose ("US dollars", "Canadian dollars" — never a bare "dollars") and
    /// the calculator has to. The count is how many of the feed's currencies claim that word.
    /// Everything unambiguous — names, signs, and 129 uncontested nouns — is generated.
    /// `pound`/`pounds` deliberately overlaps `CalcUnits`' weight; the pipeline order resolves it.
    private static let contested: [String: [String]] = [
        "USD": ["dollar", "dollars"],  // 22 claimants
        "CHF": ["franc", "francs"],  // 10
        "GBP": ["pound", "pounds"],  // 9
        "MXN": ["peso", "pesos"],  // 8
        "INR": ["rupee", "rupees"],  // 6
        "KES": ["shilling", "shillings"],  // 4
        "AED": ["dirham", "dirhams"],  // 2
        "KRW": ["won"],  // 2
        "RON": ["leu", "lei"],  // 2
        "RUB": ["ruble", "rubles"],  // 2
        "SAR": ["riyal", "riyals"],  // 2
    ]

    /// Lookup by lowercased ident. Codes, display names and uncontested nouns come from
    /// `CurrencyData.generated.swift`; `contested` above is applied last so its choices win.
    static let byName: [String: CurrencyDef] = {
        var defs: [String: CurrencyDef] = [:]
        var table: [String: CurrencyDef] = [:]
        defs.reserveCapacity(CurrencyData.all.count)
        table.reserveCapacity(CurrencyData.all.count + CurrencyData.aliases.count)
        for entry in CurrencyData.all {
            let def = CurrencyDef(code: entry.code, name: entry.name)
            defs[entry.code] = def
            table[entry.code.lowercased()] = def
        }
        for (word, code) in CurrencyData.aliases { table[word] = defs[code] }
        for (code, words) in contested {
            guard let def = defs[code] else { continue }
            for word in words { table[word] = def }
        }
        return table
    }()
}
