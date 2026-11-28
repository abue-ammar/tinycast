import Foundation
import Testing

@testable import Tinycast

extension CalcTests {
    @Test(
        arguments: [
            .display("5 usd per gallon", "3.95 GBP/gal", region: "GBP"),
            .display("$5/gal", "3.95 GBP/gal", region: "GBP"),
            .display("5 usd per gallon", "5 USD/gal"),
            .display("5 USD/gal to GBP/gal", "3.95 GBP/gal"),
            .display("100 USD / 4hr", "25 USD/hr", region: "GBP"),
            .display("5 usd per gallon to eur per liter", "1.215191441 EUR/L", region: "GBP")
        ] as [Case])
    func aRateWithNoTargetAnswersInTheRegionCurrency(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1 euro to dollars", "1.09 USD"),
            .expression("1 euro to dollars", "1 EUR"),
            .badges("1 euro to dollars", source: "Euro", target: "US Dollar"),
            .display("50 GBP in euros", "58.23 EUR"),
            .display("100 dollars to yen", "15,700.00 JPY"),
            .display("100 usd -> eur", "92.00 EUR"),
            .display("2*50 usd to eur", "92.00 EUR"),
            .display("eur to usd", "1.09 USD"),
            .copy("100 dollars to yen", "15700.00 JPY"),
            .display("100 usd eur", "92.00 EUR"),
            .display("100 usd eur", "92.00 EUR", region: "GBP"),
            .display("2*50 usd eur", "92.00 EUR"),
            .display("€20 gbp", "17.17 GBP"),
            .display("USD1K eur", "920.00 EUR"),
            .display("10 pounds euros", "11.65 EUR"),
            .error("5 usd npr", "No exchange rate for NPR."),
            .noResult("usd eur"),
            .noResult("try all"),
            .noResult("10 usd kg"),
            .display("100/4 usd to eur", "23.00 EUR"),
            .display("100/4 usd eur", "23.00 EUR"),
            .display("-5 pounds to euros", "-5.82 EUR"),
            .display("2*50 pounds to euros", "116.46 EUR"),
            .display("-5 pounds to kg", "-2.26796185 kg"),
            .error("100/4 usd to npr", "No exchange rate for NPR."),
            .error("100/4 usd to eur", "Exchange rates unavailable — check your connection.").offline,
            .error("10 kg + 5 usd to eur", "Cannot add Weight and Currency."),
            .display("€20 to GBP", "17.17 GBP"),
            .display("20€ to GBP", "17.17 GBP"),
            .display("USD1K to EUR", "920.00 EUR"),
            .display("1kUSD to EUR", "920.00 EUR"),
            .display("£50 in dollars", "63.29 USD"),
            .display("$100 to yen", "15,700.00 JPY"),
            .display("400K xof in €", "609.80 EUR"),
            .display("400K xof to €", "609.80 EUR"),
            .display("400K XOF in €", "609.80 EUR"),
            .display("400Kxof to eur", "609.80 EUR"),
            .display("400000 XoF to eur", "609.80 EUR"),
            .display("xof 400K to €", "609.80 EUR"),
            .copy("400K xof in €", "609.80 EUR"),
            .badges("400K xof in €", source: "West African CFA Franc", target: "Euro"),
            .display("100 xrp to usd", "50.00 USD"),
            .display("100XRP to usd", "50.00 USD"),
            .display("2 x 100xrp to usd", "100.00 USD"),
            .display("-100 xrp to usd", "-50.00 USD"),
            .error("400K xof in €", "Exchange rates unavailable — check your connection.").offline,
            .noResult("100 xofx to eur")
        ] as [Case])
    func currencyConvertsAgainstTheSnapshot(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1 jpy to usd", "0.006369 USD"),
            .display("1 idr to usd", "0.00005539 USD"),
            .copy("1 idr to usd", "0.00005539 USD")
        ] as [Case])
    func subCentAmountsWidenInsteadOfCollapsing(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("10 pounds to kilograms", "4.5359237 kg"),
            .display("10 pounds", "4.5359237 kg"),
            .display("10 pounds to euros", "11.65 EUR"),
            .badges("10 pounds to euros", source: "British Pound", target: "Euro"),
            .error("10 usd to kg", "Cannot convert Currency to Weight."),
            .error("10 kg to usd", "Cannot convert Weight to Currency."),
            .error("5 usd to npr", "No exchange rate for NPR."),
            .error("1 eur to usd", "Exchange rates unavailable — check your connection.").offline,
            .noResult("10 usd to nonsense"),
            .noResult("usd"),
            .noResult("btc"),
            .error("5 usd to zmw", "No exchange rate for ZMW."),
            .error("5 usd to afn", "No exchange rate for AFN.")
        ] as [Case])
    func aUnitOutranksACurrencyAndAnUnquotedCodeHasNoRate(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .noResult("1 hrk to usd"),
            .noResult("1 kuna to usd"),
            .badges("1 chf to usd", source: "Swiss Franc", target: "US Dollar"),
            .badges("1 aed to usd", source: "UAE Dirham", target: "US Dollar"),
            .error("1 zloty to usd", "No exchange rate for PLN."),
            .error("1 forint to usd", "No exchange rate for HUF."),
            .error("1 taka to usd", "No exchange rate for BDT."),
            .error("1 rand to usd", "No exchange rate for ZAR."),
            .error("1 krónur to usd", "No exchange rate for ISK."),
            .error("1 kronur to usd", "No exchange rate for ISK."),
            .display("1 franc to usd", "1.23 USD"),
            .error("1 peso to usd", "No exchange rate for MXN."),
            .noResult("1 krona to usd"),
            .error("1 rmb to usd", "No exchange rate for CNY."),
            .error("1 renminbi to usd", "No exchange rate for CNY."),
            .error("1 ntd to usd", "No exchange rate for TWD."),
            .error("1299 usd to ntd", "No exchange rate for TWD."),
            .noResult("50 quid to usd"),
            .noResult("100 bucks to eur"),
            .noResult("1 rights to usd"),
            .display("-0.0000000000001 usd to eur", "0.00 EUR"),
            .display("0 usd to eur", "0.00 EUR"),
            .display("-5 usd to eur", "-4.60 EUR"),
            .display("1 cup to ml", "236.5882365 mL")
        ] as [Case])
    func currencyNamesResolveFromTheGeneratedTable(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("10$", "10.00 USD"),
            .expression("10$", "10 USD"),
            .badges("10$", source: "Expression", target: "US Dollar"),
            .display("$10 + $5", "15.00 USD"),
            .display("10$ + 5$", "15.00 USD"),
            .display("$10 + €5", "14.20 EUR"),
            .display("€5 + $10", "15.43 USD"),
            .expression("$10 + €5", "10 USD + 5 EUR"),
            .expression("10$ + 5€", "10 USD + 5 EUR"),
            .display("$10 * 2", "20.00 USD"),
            .display("$10 / 4", "2.50 USD"),
            .display("$10 / $2", "5"),
            .display("$100 * 3%", "3.00 USD"),
            .display("3% * $100", "3.00 USD"),
            .display("$100 / 25%", "400.00 USD"),
            .display("($100 * 3%) to eur", "2.76 EUR"),
            .display("($10 + $5) to eur", "13.80 EUR")
        ] as [Case])
    func moneyArithmeticKeepsTheCurrency(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("(20 eur to usd) * 30", "652.17 USD"),
            .display("(20 eur to usd) * 20", "434.78 USD"),
            .display("(20 sgd to usd) * 30", "444.44 USD"),
            .display("2 * (20 eur to usd)", "43.48 USD"),
            .display("(20 eur to usd) / 2", "10.87 USD"),
            .display("(eur to usd) * 2", "2.17 USD"),
            .display("(20 eur to usd) + (10 gbp to usd)", "34.40 USD"),
            .display("((20 eur to usd) + 1) * 2", "45.48 USD"),
            .display("(10km to mi) * 2", "12.42742384 mi"),
            .display("(1hr + 30min to s) * 2", "10,800 s"),
            .expression("(20 eur to usd) * 30", "(20 EUR to USD) × 30"),
            .badges("(20 eur to usd) * 30", source: "Expression", target: "US Dollar"),
            .display("(20 eur to usd) *", "21.74 USD"),
            .error("(10 kg to usd) * 2", "Cannot convert Weight to Currency.")
        ] as [Case])
    func aParenthesizedConversionIsAQuantity(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .error("($10 + $5) to npr", "No exchange rate for NPR."),
            .error("(1kg + 500g) to usd", "Cannot convert Weight to Currency."),
            .display("20 eur to usd * 30", "652.17 USD"),
            .display("20 eur to usd / 2", "10.87 USD"),
            .display("20 eur to usd + 5 usd", "26.74 USD"),
            .display("1000 usd in eur/12", "76.67 EUR"),
            .copy("1000 usd in eur/12", "76.67 EUR"),
            .expression("1000 usd in eur/12", "1000 USD in EUR ÷ 12"),
            .badges("1000 usd in eur/12", source: "Expression", target: "Euro"),
            .display("1000USD in EUR/12", "76.67 EUR"),
            .display("$1000 in €/12", "76.67 EUR"),
            .display("1000 usd to eur * 2", "1,840.00 EUR"),
            .display("1000 usd → eur / 4", "230.00 EUR"),
            .display("1000 usd -> eur / 4", "230.00 EUR"),
            .display("1000 usd in eur + 20", "940.00 EUR"),
            .display("1000 usd in eur - 20", "900.00 EUR"),
            .display("1000 usd in eur * 3%", "27.60 EUR"),
            .display("1000 usd in eur / 25%", "3,680.00 EUR"),
            .display("1000 usd in eur / (2 + 3)", "184.00 EUR"),
            .display("1000 usd in eur / -2", "-460.00 EUR"),
            .display("1000 usd in eur / 2^3", "115.00 EUR"),
            .display("1000 usd in eur / 2 * 3 + 5", "1,385.00 EUR"),
            .display("(1000 usd in eur / 12) * 3", "230.00 EUR"),
            .display("1000 usd in eur / 12 +", "76.67 EUR"),
            .display("1000 usd in eur /", "920.00 EUR"),
            .display("1 btc in usd / 12", "5,000.00 USD"),
            .display("1200 xof in eur / 2", "0.91 EUR"),
            .display("10km to m / 4", "2,500 m"),
            .display("10in in cm / 2", "12.7 cm"),
            .display("20 pounds to kg / 2", "4.5359237 kg"),
            .display("500 Mbps in MBps / 2", "31.25 MBps"),
            .display("1hr to min * 2", "120 min"),
            .display("20 celsius to fahrenheit / 2", "34 °F"),
            .display("10 celsius + 20 fahrenheit in celsius + 5 celsius", "8.333333333 °C"),
            .display("100km/h in m/s / 2", "13.88888889 m/s"),
            .display("25 USD/hr in EUR/min * 2", "0.7666666667 EUR/min"),
            .display("2m2 in cm^2 / 2", "10,000 cm²"),
            .display("1kg/m3 in g/cm3 * 2", "0.002 g/cm³"),
            .display("100km/h in m/s + 2m/s", "29.77777778 m/s"),
            .display("1000 usd / 12 in eur", "76.67 EUR"),
            .display("1000 usd + 200 usd in eur", "1,104.00 EUR")
        ] as [Case])
    func arithmeticContinuesAfterAConversion(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("2 * 500 usd in eur / 4", "230.00 EUR"),
            .display("1000 usd / 4 to eur / 2", "115.00 EUR"),
            .display("1000 usd in eur / 2 to gbp + 1 gbp", "396.00 GBP"),
            .display("5 ft 3 in in cm / 2", "80.01 cm"),
            .display("5 ft 3 in in cm + 1 cm", "161.02 cm"),
            .display("100 km / 2 h in m/s / 2", "6.944444444 m/s"),
            .display("2m * 3m to cm2 + 1 cm2", "60,001 cm²"),
            .display("round(1000 usd in eur)", "920.00 EUR"),
            .display("max(1000 usd in eur, 900 eur)", "920.00 EUR"),
            .display("min(10 kg to lb, 30 lb)", "22.04622622 lb"),
            .display("max(1.000 usd in eur; 900 eur)", "920,00 EUR").localized(.italian),
            .display("1000 usd in eur > 900 eur", "true"),
            .display("10 kg to lb == 10 kg", "true"),
            .noResult("1000 usd in eur & 3"),
            .noResult("1000 usd in eur)"),
            .noResult("10 kg to lb to oz"),
            .display("1.000 usd in eur / 12", "76,67 EUR").localized(.italian),
            .noResult("1000 usd in eur / 0"),
            .noResult("1000 usd in eur / 0%"),
            .noResult("1000 usd in eur / (2 - 2)"),
            .noResult("1000 usd in eur / nonsense"),
            .noResult("1000 usd in eur / (2 +)"),
            .noResult("1000 usd in eur / 2 nonsense"),
            .noResult("1000 usd in eur nonsense / 2"),
            .noResult("1000 usd in eur / 1e-999"),
            .noResult("1000 usd in eur / 1e308 * 1e308 * 1e308"),
            .noResult("100km/h in m/s nonsense / 2"),
            .noResult("100km/h in m/s / (2 +)"),
            .error("1000 usd in npr / 12", "No exchange rate for NPR."),
            .error("1000 usd in eur / 12", "Exchange rates unavailable — check your connection.").offline,
            .error("10kg in usd / 2", "Cannot convert Weight to Currency."),
            .error("100km/h in kg/s / 2", "Cannot convert Speed to Compound Units."),
            .display("$10 +", "10.00 USD"),
            .badges("$10 +", source: "Expression", target: "US Dollar"),
            .display("$5(2)", "10.00 USD"),
            .display("5(2)$", "10.00 USD"),
            .display("$5(2) to eur", "9.20 EUR"),
            .error("$10 + 5kg", "Cannot add Currency and Weight."),
            .error("$10 + $5", "Exchange rates unavailable — check your connection.").offline,
            .error("$100 * 3%", "Exchange rates unavailable — check your connection.").offline,
            .error("10$", "Exchange rates unavailable — check your connection.").offline
        ] as [Case])
    func aMidExpressionConversionTakesTheWholeTermBeforeIt(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1 btc to usd", "60,000.00 USD"),
            .display("1 bitcoin to usd", "60,000.00 USD"),
            .display("0.5 sol to eur", "46.00 EUR"),
            .display("2 eth to gbp", "3,160.00 GBP"),
            .badges("1 eth to usd", source: "Ethereum", target: "US Dollar"),
            .display("1 usd to btc", "0.00001667 BTC"),
            .copy("1 usd to btc", "0.00001667 BTC"),
            .error("1 shib to usd", "No exchange rate for SHIB."),
            .error("1 dash to usd", "No exchange rate for DASH."),
            .error("1 neo to usd", "No exchange rate for NEO."),
            .badges("1 sol to usd", source: "Solana", target: "US Dollar"),
            .error("1 soles to usd", "No exchange rate for PEN."),
            .display("1 btc to sats", "100,000,000.00 SATS"),
            .display("1 usd to sats", "1,666.67 SATS"),
            .display("1 eth to sats", "3,333,333.33 SATS"),
            .display("10000 sats to usd", "6.00 USD"),
            .display("10000 sats", "501.00 INR", region: "INR"),
            .badges("1 eth to sats", source: "Ethereum", target: "Satoshi")
        ] as [Case])
    func cryptoIsPricedByTheSameTable(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1 usd", "83.50 INR", region: "INR"),
            .expression("1 usd", "1 USD", region: "INR"),
            .badges("1 usd", source: "US Dollar", target: "Indian Rupee", region: "INR"),
            .display("10$", "835.00 INR", region: "INR"),
            .display("1 btc", "5,010,000.00 INR", region: "INR"),
            .copy("1 usd", "83.50 INR", region: "INR"),
            .display("1 usd", "0.92 EUR", region: "USD"),
            .badges("1 usd", source: "US Dollar", target: "Euro", region: "USD"),
            .display("1 eur", "1.09 USD", region: "EUR"),
            .badges("1 eur", source: "Euro", target: "US Dollar", region: "EUR"),
            .display("1 usd", "1.00 USD", region: "NPR"),
            .display("1 usd", "1.00 USD", region: "ZZZ"),
            .display("1 usd", "1.00 USD"),
            .display("$10 + €5", "14.20 EUR", region: "INR"),
            .display("$10 +", "10.00 USD", region: "INR"),
            .badges("$10 +", source: "Expression", target: "US Dollar", region: "INR"),
            .display("1 usd to eur", "0.92 EUR", region: "INR"),
            .display("10 pounds", "4.5359237 kg", region: "INR"),
            .noResult("usd", region: "INR"),
            .noResult("btc", region: "INR")
        ] as [Case])
    func aBareAmountAnswersInTheRegionCurrency(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: ["XAF", "XPF", "XCD", "XCG", "XDR", "XAU", "XAG", "XLM", "XMR"])
    func aCodeTheSnapshotDoesNotQuoteHasNoRate(_ code: String) throws {
        let noRate = CalcResult.Payload.error(message: "No exchange rate for \(code).")
        #expect(try Self.evaluate("100 \(code.lowercased()) to usd", rates: Self.rates)?.payload == noRate)
        #expect(try Self.evaluate("100\(code) in usd", rates: Self.rates)?.payload == noRate)
    }

    @Test func theGeneratedTablesCarryTheWholeRegistry() {
        #expect(CurrencyData.all.count >= 150)
        #expect(CurrencyData.signs.count >= 20)
        #expect(CurrencyData.aliases.count >= 100)
    }

    @Test func satsAreNotAFetchedCoin() {
        #expect(!CalcCurrency.cryptoCodes.contains(CalcCurrency.satoshi.code))
    }

    @Test func cryptoIsAbsentFromTheGeneratedFiatTable() {
        let crypto = CurrencyData.all.map(\.code).filter(CalcCurrency.cryptoCodes.contains)
        #expect(crypto.isEmpty)
    }

    // MARK: Feed snapshots

    /// A pair whose base isn't the source and a nonsense rate, both of which must be dropped.
    static let fiatFeed = Data(
        #"{"success":true,"source":"USD","quotes":{"USDEUR":0.9,"EURGBP":0.8,"USDBAD":-1}}"#.utf8)
    /// Quoted the other way round: 1 BTC costs 20,000 USD, so the table stores 0.00005.
    static let cryptoFeed = Data(#"{"success":true,"target":"USD","rates":{"BTC":20000}}"#.utf8)

    @Test func aFiatOnlySnapshotIsIncomplete() throws {
        let snapshot = try CurrencyFeed.snapshot(
            fiat: Self.fiatFeed, crypto: nil, now: try Date(Self.now, strategy: .iso8601))
        #expect(snapshot.rates.rates == ["USD": 1, "EUR": 0.9])
        #expect(!snapshot.complete)
    }

    @Test func bothFeedsMakeACompleteSnapshot() throws {
        let snapshot = try CurrencyFeed.snapshot(
            fiat: Self.fiatFeed, crypto: Self.cryptoFeed, now: try Date(Self.now, strategy: .iso8601))
        #expect(snapshot.rates.rates == ["USD": 1, "EUR": 0.9, "BTC": 1.0 / 20_000])
        #expect(snapshot.complete)
    }

    @Test func aCoinFeedQuotedAgainstAnotherBaseIsIgnored() throws {
        let euroCoins = Data(#"{"success":true,"target":"EUR","rates":{"BTC":20000}}"#.utf8)
        let snapshot = try CurrencyFeed.snapshot(
            fiat: Self.fiatFeed, crypto: euroCoins, now: try Date(Self.now, strategy: .iso8601))
        #expect(snapshot.rates.rates == ["USD": 1, "EUR": 0.9])
        #expect(!snapshot.complete)
    }

    @Test(arguments: [
        #"{"success":true,"source":"USD","quotes":{}}"#,
        #"{"success":false,"source":"USD","quotes":{"USDEUR":0.9}}"#
    ])
    func aFeedWithNothingUsableThrows(_ fiat: String) throws {
        let now = try Date(Self.now, strategy: .iso8601)
        #expect(throws: (any Error).self) {
            try CurrencyFeed.snapshot(fiat: Data(fiat.utf8), crypto: nil, now: now)
        }
    }

    @Test func aCachedSnapshotThatPricesNoCoinPredatesThem() throws {
        let coinless = CurrencyRates(
            base: "USD", rates: ["EUR": 0.9], fetchedAt: try Date(Self.now, strategy: .iso8601))
        #expect(!CurrencyFeed.pricesCoins(coinless))
        #expect(coinless.rate(for: "SATS") == nil, "sats need BTC's rate")
        #expect(CurrencyFeed.pricesCoins(Self.rates))
    }
}
