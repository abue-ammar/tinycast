import Testing

@testable import Tinycast

extension CalcTests {
    @Test(
        arguments: [
            .display("2,3 + 1,5", "3,8").localized(.italian),
            .display("1.234,56 + 0,44", "1.235").localized(.italian),
            .display("10/4", "2,5").localized(.italian),
            .copy("1.234,56 + 0,44", "1235").localized(.italian),
            .copy("10/4", "2,5").localized(.italian),
            .display("2^20", "1.048.576").localized(.italian),
            .display("1.000.000 / 3", "333.333,3333").localized(.italian),
            .display("1/3", "0,3333333333").localized(.italian),
            .display(",5 + 1", "1,5").localized(.italian),
            .display("1,5e3", "1.500").localized(.italian),
            .display("2,5k", "2.500").localized(.italian),
            .display("12.345.678 + 1", "12.345.679").localized(.italian),
            .display("-1.234,5 * 2", "-2.469").localized(.italian),
            .display("2 + 2 =", "4").localized(.italian),
            .copy("2^20", "1048576").localized(.italian),
            .copy("1/3", "0,3333333333").localized(.italian)
        ] as [Case])
    func aDecimalCommaReadsAndWrites(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("max(2,5; 3)", "3").localized(.italian),
            .display("max(2,5;3,5)", "3,5").localized(.italian),
            .display("hypot(3;4)", "5").localized(.italian),
            .display("round(3,14159; 2)", "3,14").localized(.italian),
            .display("gcd(12;18;8)", "2").localized(.italian),
            .display("log(8;2)", "3").localized(.italian),
            .display("max(1.000; 999)", "1.000").localized(.italian),
            .display("max(2,3)", "2,3").localized(.italian),
            .display("hypot(3m;400cm)", "5 m").localized(.italian),
            .expression("hypot(3m;400cm)", "hypot(3 m; 400 cm)").localized(.italian),
            .expression("max(2,5;3)", "max(2,5; 3)").localized(.italian),
            .display("max(2, 3)", "3").localized(.italian),
            .display("average of 10; 20; 30", "20").localized(.italian),
            .display("average of 10, 20, 30", "20").localized(.italian),
            .display("sum of 1,5; 2,5", "4").localized(.italian)
        ] as [Case])
    func functionArgumentsTakeASemicolon(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .noResult("1,2,3").localized(.italian),
            .noResult("1.5 + 1").localized(.italian),
            .noResult("1.23,4 + 1").localized(.italian),
            .noResult("1,234.5 + 1").localized(.italian),
            .noResult("12.34 * 2").localized(.italian),
            .noResult("1.2345 + 1").localized(.italian)
        ] as [Case])
    func aNumberWithNoSingleReadingHasNoResult(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1 + 2,", "3").localized(.italian),
            .display("2,5 +", "2,5").localized(.italian),
            .expression("2,5 +", "2,5 +").localized(.italian),
            .expression("1.234,5 *", "1234,5 ×").localized(.italian)
        ] as [Case])
    func partialInputKeepsTheCard(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1,5km to m", "1.500 m").localized(.italian),
            .display("10kg + 500g", "10.500 g").localized(.italian),
            .display("2,5 hours to min", "150 min").localized(.italian),
            .display("5feet + 1m", "2,524 m").localized(.italian),
            .copy("1,5km to m", "1500 m").localized(.italian),
            .display("€1.234,50 to usd", "1.341,85 USD").localized(.italian),
            .copy("€1.234,50 to usd", "1341,85 USD").localized(.italian),
            .display("$10 + 5", "15,00 USD").localized(.italian),
            .display("20% off 1.500", "1.200").localized(.italian),
            .display("0x1000", "4.096").localized(.italian),
            .display("255 to hex", "0xFF").localized(.italian),
            .copy("0x1000", "4096").localized(.italian),
            .expression("1,5km to m", "1,5 km").localized(.italian)
        ] as [Case])
    func unitsCurrencyAndPercentRenderThroughTheFormat(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1970-01-01T00:00:00Z + 1h to unix", "3.600").localized(.italian),
            .display("hrs till 9am", "8,7 hours").localized(.italian)
        ] as [Case])
    func datesAndClocksSkipTheNumberRewrite(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1\u{202F}234,5 + 0,5", "1\u{202F}235").localized(.french),
            .display("2^20", "1\u{202F}048\u{202F}576").localized(.french),
            .display("max(1,5; 2)", "2").localized(.french),
            .display("1.5 + 1", "2,5").localized(.french)
        ] as [Case])
    func spaceGroupingIsTheNarrowNoBreakSpace(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1\u{2019}234.5 + 0.5", "1\u{2019}235").localized(.swiss),
            .display("max(1,2)", "2").localized(.swiss),
            .display("1,000 + 234", "1\u{2019}234").localized(.swiss),
            .display("10/4", "2.5").localized(.swiss)
        ] as [Case])
    func apostropheGroupingKeepsTheCommaForArguments(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("2000000 + 0", "20,00,000").localized(.indian),
            .display("100000 + 0", "1,00,000").localized(.indian),
            .display("12345678 + 0", "1,23,45,678").localized(.indian),
            .display("123456789 + 0", "12,34,56,789").localized(.indian),
            .display("123456.78 * 1", "1,23,456.78").localized(.indian),
            .display("20,00,000 + 1", "20,00,001").localized(.indian),
            .display("1,23,45,678 / 2", "61,72,839").localized(.indian),
            .display("1/3", "0.3333333333").localized(.indian),
            .display("2,000,000 + 1", "20,00,001").localized(.indian),
            .copy("2000000 + 0", "2000000").localized(.indian),
            .display("2,3 + 1,5", "38").localized(.indian),
            .display("2000000 + 0", "2.000.000").localized(.indianComma),
            .display("2.000.000 + 1", "2.000.001").localized(.indianComma)
        ] as [Case])
    func indianGroupingIsThreeThenTwo(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1234,5 * 2", "2469").localized(.ungrouped),
            .display("2^20", "1048576").localized(.ungrouped),
            .display("1.234 + 1", "2,234").localized(.ungrouped)
        ] as [Case])
    func aFormatWithoutGroupingNeitherReadsNorWrites(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1,000 + 234", "1,234").localized(.english),
            .display("max(2,3)", "3").localized(.english),
            .noResult("max(2;3)").localized(.english)
        ] as [Case])
    func englishStaysByteForByte(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .expression("max(1,234)", "max(1,234)").localized(.swiss),
            .display("max(1;234)", "234").localized(.italian)
        ] as [Case])
    func aCallKeepsItsArgumentsInTheFormat(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    // MARK: The format itself

    @Test func englishSeparatorsAreTheEnglishFormat() {
        #expect(CalcNumberFormat(decimalSeparator: ".", groupingSeparator: ",") == .english)
    }

    @Test func anArabicDecimalHasNoFormat() {
        #expect(CalcNumberFormat(decimalSeparator: "\u{066B}", groupingSeparator: "\u{066C}") == nil)
    }

    @Test(arguments: [",", " "])
    func aGroupingTheDecimalOrATypedSpaceWouldClashWithIsDropped(_ grouping: String) {
        #expect(
            CalcNumberFormat(decimalSeparator: ",", groupingSeparator: grouping)?.groupingSeparator == nil)
    }

    @Test(arguments: [(Separators.italian, ";" as Character), (.swiss, ",")])
    func argumentsSplitOnWhatTheDecimalLeavesFree(_ separators: Separators, _ argument: Character) throws {
        #expect(try separators.format().argumentSeparator == argument)
    }

    @Test(arguments: [
        (".", ",", 3, 3) as (String, String?, Int, Int), (",", nil, 3, 2), (",", ".", 3, 2), (".", "'", 3, 2)
    ])
    func aSecondaryWidthNeedsEnglishSeparatorsAndADifferentWidth(
        _ decimal: String, _ grouping: String?, _ primary: Int, _ secondary: Int
    ) {
        let format = CalcNumberFormat(
            decimalSeparator: decimal, groupingSeparator: grouping, primaryGrouping: primary,
            secondaryGrouping: secondary)
        #expect(format?.secondaryGrouping == nil)
    }

    @Test(arguments: [(".", ",", 2), (",", "\u{00A0}", 3)])
    func aPrimaryWidthOtherThanThreeNeedsEnglishSeparators(
        _ decimal: String, _ grouping: String, _ width: Int
    ) {
        let format = CalcNumberFormat(
            decimalSeparator: decimal, groupingSeparator: grouping, primaryGrouping: 2)
        #expect(format?.primaryGrouping == width)
    }

    @Test(arguments: [
        (Separators.italian, "17.2.26 + 100 weekdays"), (.italian, "25.8.27"), (.italian, "25. aug"),
        (.italian, "25. aug + 3"), (.italian, "time in Tokyo"),
        (.italian, "1970-01-01T00:00:00.125Z to unix ms"),
        (.italian, "1.2.3 + 1"), (.italian, "7:30 - 13:30"), (.italian, "days until 29.10"),
        (.italian, "days since 20.7."), (.swiss, "19.2.27"), (.swiss, "1.2.3 + 1")
    ])
    func textWithNoDecimalInItAnswersAsInEnglish(_ separators: Separators, _ query: String) throws {
        let format = try separators.format()
        let english = try Self.evaluate(query, rates: Self.rates)
        let localized = try Self.evaluate(query, rates: Self.rates, format: format).map(format.localized)
        #expect(localized == english)
    }

    // MARK: History

    @Test(arguments: [
        (Separators.italian, "1,234.5 kg", "1.234,5 kg"), (.italian, "19.2.27", "19.2.27"),
        (.italian, "00:18:00.123", "00:18:00.123"),
        (.italian, "Friday, 24 July 2026", "Friday, 24 July 2026"),
        (.italian, "1.524157875e+16", "1,524157875e+16"), (.english, "1,234.5", "1,234.5")
    ])
    func historyRedrawsAnAnswerInTheFormat(
        _ separators: Separators, _ answer: String, _ redrawn: String
    ) throws {
        #expect(try separators.format().localized(answer) == redrawn)
    }

    @Test(arguments: [
        (Separators.italian, "max(1.5, 2)", "max(1,5; 2)"), (.italian, "max(2,3)", "max(2;3)"),
        (.italian, "max(1,234) + 1,234", "max(1;234) + 1.234"),
        (.italian, "round(3.14159,2)", "round(3,14159;2)"),
        (.italian, "2max(1, min(2,3))", "2max(1; min(2;3))"), (.swiss, "max(1,234)", "max(1,234)")
    ])
    func historyRedrawsAnExpressionsArguments(
        _ separators: Separators, _ expression: String, _ redrawn: String
    ) throws {
        #expect(try separators.format().localizedExpression(expression) == redrawn)
    }

    @Test func historySearchReadsTheFormatBackToCanonical() throws {
        #expect(try Separators.italian.format().canonical("3,8") == "3.8")
    }
}
