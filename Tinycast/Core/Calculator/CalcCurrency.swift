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
    static func parseConversion(_ tokens: [CalcToken], rates: CurrencyRates?) -> ConversionParse? {
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

    /// Currency sign → the tokenizer's lowercased ident form. `¥` resolves to JPY and `$` to USD — the other claimants (CNY, CAD, AUD…) need their code.
    static let symbols: [Character: String] = [
        "$": "usd", "€": "eur", "£": "gbp", "¥": "jpy", "₹": "inr", "₩": "krw",
        "₽": "rub", "₺": "try", "₪": "ils", "₫": "vnd", "฿": "thb", "₴": "uah",
        "₦": "ngn", "₱": "php",
    ]

    /// Lookup by lowercased ident: ISO code, singular/plural name, and common nicknames. `pound`/`pounds` deliberately overlaps `CalcUnits`' weight — the pipeline order resolves it.
    static let byName: [String: CurrencyDef] = {
        var table: [String: CurrencyDef] = [:]
        func add(_ code: String, _ name: String, _ aliases: [String] = []) {
            let def = CurrencyDef(code: code, name: name)
            table[code.lowercased()] = def
            for alias in aliases { table[alias] = def }
        }

        add("USD", "US Dollar", ["dollar", "dollars", "buck", "bucks"])
        add("EUR", "Euro", ["euro", "euros"])
        add("GBP", "British Pound", ["pound", "pounds", "sterling", "quid"])
        add("JPY", "Japanese Yen", ["yen"])
        add("CHF", "Swiss Franc", ["franc", "francs"])
        add("CAD", "Canadian Dollar")
        add("AUD", "Australian Dollar")
        add("NZD", "New Zealand Dollar")
        add("CNY", "Chinese Yuan", ["yuan", "renminbi", "rmb"])
        add("HKD", "Hong Kong Dollar")
        add("SGD", "Singapore Dollar")
        add("INR", "Indian Rupee", ["rupee", "rupees"])
        add("KRW", "South Korean Won", ["won"])
        add("TWD", "Taiwan Dollar")
        add("THB", "Thai Baht", ["baht"])
        add("MYR", "Malaysian Ringgit", ["ringgit"])
        add("IDR", "Indonesian Rupiah", ["rupiah"])
        add("PHP", "Philippine Peso")
        add("VND", "Vietnamese Dong", ["dong"])
        add("RUB", "Russian Ruble", ["ruble", "rubles", "rouble", "roubles"])
        add("TRY", "Turkish Lira", ["lira"])
        add("PLN", "Polish Zloty", ["zloty"])
        add("CZK", "Czech Koruna", ["koruna"])
        add("HUF", "Hungarian Forint", ["forint"])
        add("RON", "Romanian Leu", ["leu", "lei"])
        add("SEK", "Swedish Krona")
        add("NOK", "Norwegian Krone")
        add("DKK", "Danish Krone")
        add("ISK", "Icelandic Krona")
        add("ILS", "Israeli Shekel", ["shekel", "shekels"])
        add("AED", "UAE Dirham", ["dirham", "dirhams"])
        add("SAR", "Saudi Riyal", ["riyal", "riyals"])
        add("QAR", "Qatari Riyal")
        add("EGP", "Egyptian Pound")
        add("ZAR", "South African Rand", ["rand"])
        add("NGN", "Nigerian Naira", ["naira"])
        add("KES", "Kenyan Shilling", ["shilling", "shillings"])
        add("MAD", "Moroccan Dirham")
        add("BRL", "Brazilian Real", ["real", "reais"])
        add("MXN", "Mexican Peso", ["peso", "pesos"])
        add("ARS", "Argentine Peso")
        add("CLP", "Chilean Peso")
        add("COP", "Colombian Peso")
        add("PEN", "Peruvian Sol")
        add("UAH", "Ukrainian Hryvnia", ["hryvnia"])
        add("PKR", "Pakistani Rupee")
        add("BDT", "Bangladeshi Taka", ["taka"])
        add("LKR", "Sri Lankan Rupee")
        add("NPR", "Nepalese Rupee")

        return table
    }()
}
