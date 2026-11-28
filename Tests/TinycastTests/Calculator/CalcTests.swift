import Foundation
import Testing

@testable import Tinycast

struct CalcTests {
    /// Friday 24 July 2026, 12:18 AM UTC: the clock every case is asked at unless it names one.
    static let now = "2026-07-24T00:18:00Z"
    static let septemberNoon = "2026-09-15T12:00:00Z"
    static let homeZones = ["UTC", "Asia/Shanghai", "America/Los_Angeles"]

    /// NPR is absent on purpose: a recognized code must reach "no exchange rate", not no card.
    static let rates = CurrencyRates(
        base: "USD",
        rates: [
            "USD": 1, "EUR": 0.92, "GBP": 0.79, "JPY": 157, "INR": 83.5, "CAD": 1.36,
            "KRW": 1330, "IDR": 18053, "CHF": 0.81, "AED": 3.6725, "SGD": 1.35,
            "XOF": 603.48, "XRP": 2,
            "BTC": 1.0 / 60_000, "ETH": 1.0 / 2_000, "SOL": 1.0 / 100, "DOGE": 10
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_785_000_000))

    static func evaluate(
        _ query: String, at now: String = CalcTests.now, zone: String = "UTC", locale: String = "en_US",
        rates: CurrencyRates? = nil, region: String? = nil, format: CalcNumberFormat = .english
    ) throws -> CalcResult? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        calendar.locale = Locale(identifier: locale)
        return CalcEngine.evaluate(
            query, now: try Date(now, strategy: .iso8601), calendar: calendar, rates: rates,
            region: region, format: format)
    }

    @Test func aHundredTermSumStillAnswers() throws {
        let row = Case.display(String(repeating: "1+", count: 100) + "1", "101")
        #expect(try row.actual() == row.expected)
    }

    @Test func tooDeepAnExpressionHasNoResult() throws {
        #expect(try Self.evaluate(String(repeating: "1+", count: 128) + "1", rates: Self.rates) == nil)
    }

    @Test(arguments: [
        "2^10", "1/3", "100 usd to eur", "10 km to mi", "1m", "255 to hex", "145 mins to timespan",
        "20% off 500", "2^10 +"
    ])
    func aNumericAnswerChainsIntoTheNextQuery(_ query: String) throws {
        let result = try #require(try Self.evaluate(query, rates: Self.rates))
        #expect(result.canChain)
    }

    @Test(arguments: [
        "now + 90 min", "now + 90 min +", "today", "time", "time in Tokyo", "3pm London in Tokyo", "5 > 3",
        "ratio of 1920 to 1080"
    ])
    func aMomentATruthOrARatioDoesNotChain(_ query: String) throws {
        let result = try #require(try Self.evaluate(query, rates: Self.rates))
        #expect(!result.canChain)
    }

    @Test func aLocalizedMomentDoesNotChain() throws {
        let italian = try Separators.italian.format()
        let result = try #require(try Self.evaluate("now + 90 min", rates: Self.rates, format: italian))
        #expect(!italian.localized(result).canChain)
    }

    @Test(arguments: [
        .display("2+2", "4"),
        .display("5*7", "35"),
        .display("100/4", "25"),
        .display("2^10", "1,024"),
        .display("2^3^2", "512"),
        .display("2 square root of 9", "6"),
        .display("square root of 25m2", "5 m"),
        .display("cube root of -8m3", "-2 m"),
        .display("cube root of 8%", "0.430886938"),
        .display("cube root of -8%", "-0.430886938"),
        .display("2 * (3 + 4) << 1", "28"),
        .display("1 ≤ 2", "true"),
        .display("2 ≠ 3", "true"),
        .display("2 ⊻ 3", "1"),
        .display("1µs to ns", "1,000 ns"),
        .display("1μs to ns", "1,000 ns"),
        .display("2\u{00A0}+\u{2009}2", "4"),
        .error("10 colo\u{0301}n to usd", "No exchange rate for CRC."),
        .copy("-9007199254740992 + 0", "-9007199254740992"),
        .copy("-0 * 1234", "0"),
        .expression("10k +", "10k +"),
        .expression("45+", "45+"),
        .expression("(2)+", "(2)+"),
        .display("2m / 2m to hex", "0x1"),
        .display("2**2", "4"),
        .display("2**10", "1,024"),
        .display("2**3**2", "512"),
        .display("(5+2)*3", "21"),
        .display("5!", "120"),
        .display("3!!", "720"),
        .display("-5+3", "-2"),
        .display("-2^2", "-4"),
        .display("10/4", "2.5"),
        .display("1/3", "0.3333333333"),
        .display("2.5 * 4", "10"),
        .display("1,000 + 234", "1,234")
    ] as [Case])
    func arithmeticReadsEveryOperatorSpelling(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10k", "10,000"),
        .copy("10k", "10000"),
        .display("2.5K", "2,500"),
        .display("10k + 500", "10,500"),
        .display("10k * 2", "20,000"),
        .badges("10k", source: "Expression", target: "Result")
    ] as [Case])
    func anAttachedKIsAThousandsSuffix(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("13 million", "13,000,000"),
        .copy("1.5 billion", "1500000000"),
        .display("2 Thousand + 1", "2,001"),
        .display("3million / 2", "1,500,000"),
        .display("13 million idr to usd", "720.10 USD"),
        .display("1.5 million idr to sgd", "112.17 SGD"),
        .display("IDR 13 million to usd", "720.10 USD"),
        .display("10% of 2 million", "200,000"),
        .expression("13 million +", "13 million +"),
        .badges("13 million", source: "Expression", target: "Result"),
        .noResult("million"),
        .noResult("2 * million"),
        .noResult("(2 + 3) million"),
        .noResult("13 millions"),
        .noResult("13 million2"),
        .noResult("1e308 billion"),
        .display("10 milliseconds to s", "0.01 s"),
        .display("1,5 million", "1.500.000").localized(.italian)
    ] as [Case])
    func magnitudeWordsScaleTheNumberBeforeThem(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("1e6 + 1", "1,000,001"),
        .display("1.5e-3 * 2", "0.003"),
        .display("2.5e8 / 2", "125,000,000"),
        .display("1E6 + 1", "1,000,001"),
        .display("1e6", "1,000,000"),
        .display("10em", "160 px"),
        .display("1e3k + 1", "1,000,001")
    ] as [Case])
    func exponentShorthandIsANumber(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("2^49", "562,949,953,421,312"),
        .display("2^50", "1,125,899,906,842,624"),
        .copy("2^50", "1125899906842624"),
        .display("999999999999999 + 1", "1,000,000,000,000,000"),
        .display("123456789 * 123456789", "1.524157875e+16")
    ] as [Case])
    func integersStayExactUpToTwoToTheFiftyThird(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("sqrt(64)", "8"),
        .display("sqrt 64", "8"),
        .display("sqrt 64 + 36", "44"),
        .display("log(1000)", "3"),
        .display("ln(e)", "1"),
        .display("sin(30deg)", "0.5"),
        .display("cos(60deg)", "0.5"),
        .display("tan(45deg)", "1"),
        .display("sin(pi/2)", "1"),
        .display("abs(-4)", "4"),
        .display("floor(2.7)", "2"),
        .display("ceil(2.1)", "3"),
        .display("round(2.5)", "3"),
        .display("SQRT(64)", "8"),
        .display("2*pi", "6.283185307"),
        .display("π*2", "6.283185307"),
        .display("e^2", "7.389056099")
    ] as [Case])
    func functionsAndConstantsEvaluate(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("4(2+3)", "20"),
        .display("(2+3)(2+3)", "25"),
        .display("2pi", "6.283185307"),
        .display("2π", "6.283185307"),
        .display("2sqrt(9)", "6"),
        .display("2(3+1)+1", "9"),
        .display("10π ^e", "224.5915772"),
        .display("3x3", "9"),
        .display("3 x 3", "9"),
        .display("3X3", "9"),
        .display("3 x -2", "-6"),
        .display("2xpi", "6.283185307"),
        .display("2xsin(pi/2)", "2"),
        .display("6/2x(1+2)", "9"),
        .display("10 x", "10"),
        .display("$5 x 2", "10.00 USD"),
        .noResult("x"),
        .noResult("x3"),
        .noResult("3x"),
        .display("2(3)kg", "6 kg"),
        .display("2*(3)kg", "6 kg"),
        .display("2(3)kg x 2", "12 kg")
    ] as [Case])
    func juxtapositionMultipliesLikeAnExplicitTimes(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("1e5", "100,000"),
        .display("2e10", "20,000,000,000"),
        .display("1E5", "100,000"),
        .display("1.5e3", "1,500"),
        .display("3e+2", "300"),
        .copy("1e-5", "1e-05"),
        .display("2e10/2", "10,000,000,000"),
        .display("1e5 to hex", "0x186A0"),
        .display("5e-3km", "0.003106855961 mi"),
        .display("2e", "5.436563657"),
        .display("1 e", "2.718281828"),
        .noResult("1e400"),
        .noResult("1e308k"),
        .noResult("-1e308k"),
        .noResult("1e308k to hex"),
        .noResult("1e308 * 2 > 1"),
        .noResult("1e308m + 1e308m > 0m"),
        .noResult("1e308m == 1e308km"),
        .noResult("(1e308 * 2) ^ 0"),
        .display("1e305k", "1e+308"),
        .noResult("1e5e5")
    ] as [Case])
    func scientificNotationOnlyWhenTheExponentHugsTheMantissa(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("20% of 450", "90"),
        .display("450 + 20%", "540"),
        .display("450 - 15%", "382.5"),
        .display("20%", "0.2")
    ] as [Case])
    func aPercentApplies(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10 mod 3", "1"),
        .display("17 mod 5", "2"),
        .display("10k mod 3", "1"),
        .display("-10 mod 3", "-1"),
        .display("2 + 10 mod 3", "3"),
        .noResult("10 mod 0"),
        .display("10 % 3", "1"),
        .display("12 % 5", "2"),
        .display("2 + 10 % 3", "3"),
        .display("(2 + 3) % 2", "1"),
        .display("12%(2+3)", "0.6"),
        .noResult("15% 80"),
        .noResult("10%3"),
        .noResult("10 % 3%"),
        .noResult("10% 20%"),
        .noResult("molar mass of cococococococococococococococococococococococococococococococox"),
        .noResult("molar mass of H99999999999999999999")
    ] as [Case])
    func aRemainderIsSpelledOutOrSpaced(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("15% decrease from 813", "691.05"),
        .display("(15% tip on $80) / 2", "6.00 USD"),
        .display("((15% off 80) + 2) * 2", "140"),
        .display("(25% off $60) split 3", "15.00 USD"),
        .display("(c4 to hz) * 2", "523.2511306 Hz"),
        .display("(2m)", "2 m"),
        .display("(15% tip on $80)", "12.00 USD"),
        .display("(pi)", "3.141592654"),
        .noResult("(µs)"),
        .noResult("1000 usd in eur / (2 +)"),
        .display("15% increase on 813", "934.95"),
        .display("450 + 20% - 5", "535")
    ] as [Case])
    func aParenthesizedPhraseIsAnOperand(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .badges("0b1010", source: "Binary", target: "Decimal"),
        .badges("0o17", source: "Octal", target: "Decimal"),
        .badges("0B1010 +", source: "Binary", target: "Decimal"),
        .badges("0O17 +", source: "Octal", target: "Decimal"),
        .copy("1.00000000004m to pm +", "1000000000040 pm"),
        .copy("1.00000000004m to pm **", "1000000000040 pm"),
        .copy("1.00000000004m to pm + =", "1000000000040 pm"),
        .copy("1.00000000004m to pm + +", "1000000000040 pm"),
        .copy("1.00000000004 * 1e12 to hex +", "0xE8D4A51028"),
        .display("255 to hex", "0xFF"),
        .display("255 to binary", "0b11111111"),
        .display("0xff to decimal", "255"),
        .display("0b1010 to decimal", "10"),
        .display("255 to octal", "0o377"),
        .display("0xff", "255")
    ] as [Case])
    func numberBasesConvert(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .noResult("safari"),
        .noResult("1password"),
        .noResult("45"),
        .noResult("3.14"),
        .noResult("pi"),
        .noResult("e"),
        .noResult("10km to"),
        .noResult("10 to mi"),
        .display("45+", "45"),
        .noResult("sqrt()"),
        .noResult("2.5!"),
        .noResult("")
    ] as [Case])
    func wordsBareNumbersAndHalfTypedInputHaveNoResult(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("hypot(3,4)", "5"),
        .display("2hypot(3,4)", "10"),
        .display("round(3.14159,2)", "3.14"),
        .display("round(1234,-2)", "1,200"),
        .display("log(8,2)", "3"),
        .display("gcd(12,18,8)", "2"),
        .display("lcm(4,6)", "12"),
        .display("atan2(1,1)*4", "3.141592654"),
        .display("root(-8,3)", "-2"),
        .display("hypot(3m,400cm)", "5 m"),
        .display("min(1km,999m)", "0.999 km"),
        .display("sum(1km,500m)", "1.5 km"),
        .display("round(2.567km,1)", "2.6 km"),
        .error("min(1km,1hr)", "Cannot compare values with different dimensions."),
        .noResult("gcd(1.5,2)"),
        .noResult("lcm(9223372036854775807,2)"),
        .noResult("round(1,9999)"),
        .display("1 << 8", "256"),
        .display("256 >> 2", "64"),
        .display("6 & 3", "2"),
        .display("5 xor 3", "6"),
        .display("5 XOR 3", "6"),
        .display("~1", "-2"),
        .display("1 | 2 == 3", "true"),
        .display("~1 == -2", "true"),
        .display("1km == 1000m", "true"),
        .display("30min >= 1hr", "false"),
        .noResult("1 << 64"),
        .noResult("1 << -1"),
        .noResult("1 << 63"),
        .noResult("9007199254740993 & 1"),
        .noResult("0x20000000000001 & 1"),
        .display("5 mod 2 == 1", "true"),
        .expression("1 << 8 == 256", "1 << 8 == 256"),
        .noResult("(1 == 1)kg"),
        .noResult("-(1 == 1)"),
        .noResult("sqrt(1 == 1)")
    ] as [Case])
    func multiArgumentFunctionsBitwiseOperatorsAndComparisons(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("1234567*1", "1,234,567"),
        .copy("1234567*1", "1234567"),
        .copy("10km to mi", "6.213711922 mi"),
        .display("-1234.5-0.25", "-1,234.75"),
        .expression("3*3", "3×3"),
        .expression("10km to mi", "10 km"),
        .badges("10km to mi", source: "Kilometers", target: "Miles"),
        .badges("100 C to F", source: "Celsius", target: "Fahrenheit")
    ] as [Case])
    func theCopyIsUngroupedAndTheExpressionIsEchoed(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10 +", "10"),
        .display("10 -", "10"),
        .display("10 *", "10"),
        .display("10 /", "10"),
        .display("10 ^", "10"),
        .display("10k +", "10,000"),
        .copy("10k +", "10000"),
        .display("10kg *", "10 kg"),
        .display("10kg + 500g +", "10,500 g"),
        .display("(10kg + 500g) *", "10,500 g"),
        .display("10kg * 3% +", "0.3 kg"),
        .display("20% of 450 +", "90"),
        .badges("10 +", source: "Expression", target: "Result"),
        .badges("10kg *", source: "Expression", target: "Kilograms"),
        .noResult("+"),
        .noResult("10 + nonsense"),
        .noResult("10 + ("),
        .noResult("10 of")
    ] as [Case])
    func aTrailingOperatorKeepsTheLastResult(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("85 + 20% split 3", "34"),
        .display("split 120 between 4", "30"),
        .display("split $120 between 4", "30.00 USD"),
        .display("$120 split 4", "30.00 USD", region: "GBP"),
        .display("120 split 4 ways", "30"),
        .display("120 / 4 people", "30"),
        .display("20% tip on 85 split 3", "5.666666667"),
        .display("10 kg split 4", "2.5 kg"),
        .display("eur 99 among 3 friends", "33.00 EUR"),
        .display("$1 / 6 split 2", "0.08 USD"),
        .display("150 min to timespan split 2", "1 hr 15 min"),
        .display("$120 to eur split 4", "27.60 EUR"),
        .badges("85 + 20% split 3", source: "Expression", target: "Per Person"),
        .noResult("split screen"),
        .noResult("120 split 0"),
        .noResult("split")
    ] as [Case])
    func splittingSharesTheUnroundedWhole(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("2*128 to hex", "0x100"),
        .display("10*5 to hex", "0x32"),
        .display("20% off 500", "400"),
        .display("50 as % of 200", "25%"),
        .badges("255 to hex", source: "Decimal", target: "Hexadecimal"),
        .badges("0xff to decimal", source: "Hexadecimal", target: "Decimal"),
        .badges("3*3", source: "Expression", target: "Result"),
        .badges("20% off 500", source: "Expression", target: "Discounted")
    ] as [Case])
    func theBadgesNameWhatWasCalculated(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("cot(1)", "0.6420926159"),
        .display("sec(1)", "1.850815718"),
        .display("csc(1)", "1.188395106"),
        .display("asin(1)", "1.570796327"),
        .display("acos(1)", "0"),
        .display("arctan(1)", "0.7853981634"),
        .display("sinh(1)", "1.175201194"),
        .display("tanh(0)", "0"),
        .display("cbrt(27)", "3"),
        .display("log2(1024)", "10"),
        .display("exp(0)", "1"),
        .display("sign(-5)", "-1"),
        .display("trunc(3.7)", "3"),
        .display("2 tau", "12.56637061"),
        .display("phi * 2", "3.236067977"),
        .display("10 sec to min", "0.1666666667 min"),
        .display("30 sec + 1 min", "1.5 min")
    ] as [Case])
    func moreFunctionsAndConstantsEvaluate(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("15% tip on 42", "6.3"),
        .display("20% tip of 80", "16"),
        .display("50 is what % of 200", "25%"),
        .display("30 is 20% of what", "150"),
        .display("ratio of 3 to 5", "3 : 5"),
        .display("ratio of 4 to 6", "2 : 3"),
        .display("ratio of 1920 to 1080", "16 : 9"),
        .badges("15% tip on 42", source: "Expression", target: "Tip")
    ] as [Case])
    func tipsAndRatios(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("average of 10, 20, 30", "20"),
        .display("avg of 1 and 2 and 3", "2"),
        .display("sum of 10, 20, 30", "60"),
        .display("max of 4, 9, 2", "9"),
        .display("min of 4, 9, 2", "2"),
        .display("sum of 2*3, 4", "10"),
        .display("round 47 to nearest 5", "45"),
        .display("round 12.3 to nearest 0.5", "12.5"),
        .display("1,000 + 234", "1,234"),
        .noResult("average of 5"),
        .noResult("10,5")
    ] as [Case])
    func listAggregatesAndSnapping(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .noResult("round is next round to"),
        .noResult(": from to at sf").offline,
        .noResult("round to"),
        .noResult("round 5 to"),
        .noResult(": at sf").offline,
        .noResult("is what % of"),
        .noResult("tip on")
    ] as [Case])
    func malformedInputAFuzzerFoundHasNoResult(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("square root of 625", "25"),
        .display("square root of 64", "8"),
        .display("cube root of 27", "3"),
        .display("2 power 10", "1,024"),
        .display("2 power 3 power 2", "512")
    ] as [Case])
    func spokenRootsAndPowers(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }
}

extension CalcTests {
    /// A query, the moment, zone and rates it is asked with, and the part of its answer it pins.
    struct Case: Sendable, CustomTestStringConvertible {
        enum Answer: Equatable, Sendable {
            case display(String)
            case copy(String)
            case expression(String)
            case badges(source: String?, target: String?)
            case error(String)
            case noResult
        }

        let query: String
        let expected: Answer
        let region: String?
        var rates: CurrencyRates? = CalcTests.rates
        var now = CalcTests.now
        var zone = "UTC"
        var locale = "en_US"
        var separators: Separators?

        init(_ query: String, _ expected: Answer, region: String? = nil) {
            self.query = query
            self.expected = expected
            self.region = region
        }

        static func display(_ query: String, _ display: String, region: String? = nil) -> Case {
            Case(query, .display(display), region: region)
        }

        static func copy(_ query: String, _ copy: String, region: String? = nil) -> Case {
            Case(query, .copy(copy), region: region)
        }

        static func expression(_ query: String, _ expression: String, region: String? = nil) -> Case {
            Case(query, .expression(expression), region: region)
        }

        static func badges(_ query: String, source: String, target: String, region: String? = nil) -> Case {
            Case(query, .badges(source: source, target: target), region: region)
        }

        static func error(_ query: String, _ message: String) -> Case {
            Case(query, .error(message))
        }

        static func noResult(_ query: String, region: String? = nil) -> Case {
            Case(query, .noResult, region: region)
        }

        /// Asked before any exchange-rate snapshot has landed.
        var offline: Case {
            var changed = self
            changed.rates = nil
            return changed
        }

        func at(_ now: String) -> Case {
            var changed = self
            changed.now = now
            return changed
        }

        func inZone(_ zone: String) -> Case {
            var changed = self
            changed.zone = zone
            return changed
        }

        func withLocale(_ locale: String) -> Case {
            var changed = self
            changed.locale = locale
            return changed
        }

        /// Typed and answered in another number format, as the palette renders it.
        func localized(_ separators: Separators) -> Case {
            var changed = self
            changed.separators = separators
            return changed
        }

        func actual() throws -> Answer {
            let format = try separators?.format()
            let evaluated = try CalcTests.evaluate(
                query, at: now, zone: zone, locale: locale, rates: rates, region: region,
                format: format ?? .english)
            guard let result = evaluated.map({ format?.localized($0) ?? $0 }) else { return .noResult }
            switch (expected, result.payload) {
            case (.display, .value(let display, _)): return .display(display)
            case (.copy, .value(_, let copy)): return .copy(copy)
            case (.expression, _): return .expression(result.expression)
            case (.badges, _): return .badges(source: result.sourceBadge, target: result.targetBadge)
            case (_, .value(let display, _)): return .display(display)
            case (_, .error(let message)): return .error(message)
            }
        }

        var testDescription: String {
            let context = [
                region.map { "region \($0)" }, rates == nil ? "offline" : nil,
                now == CalcTests.now ? nil : now, zone == "UTC" ? nil : zone,
                locale == "en_US" ? nil : locale, separators.map { "\($0)" }
            ].compactMap(\.self)
            let suffix = context.isEmpty ? "" : " (\(context.joined(separator: ", ")))"
            return "\(query) → \(expected)\(suffix)"
        }
    }

    enum Separators: Sendable {
        case english, italian, french, swiss, ungrouped, indian, indianComma

        func format() throws -> CalcNumberFormat {
            switch self {
            case .english:
                return .english
            case .italian:
                return try #require(CalcNumberFormat(decimalSeparator: ",", groupingSeparator: "."))
            case .french:
                return try #require(CalcNumberFormat(decimalSeparator: ",", groupingSeparator: "\u{202F}"))
            case .swiss:
                return try #require(CalcNumberFormat(decimalSeparator: ".", groupingSeparator: "\u{2019}"))
            case .ungrouped:
                return try #require(CalcNumberFormat(decimalSeparator: ",", groupingSeparator: nil))
            case .indian:
                return try #require(
                    CalcNumberFormat(
                        decimalSeparator: ".", groupingSeparator: ",", primaryGrouping: 3, secondaryGrouping: 2))
            case .indianComma:
                return try #require(
                    CalcNumberFormat(
                        decimalSeparator: ",", groupingSeparator: ".", primaryGrouping: 3, secondaryGrouping: 2))
            }
        }
    }
}
