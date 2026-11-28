import Testing

@testable import Tinycast

extension CalcTests {
    @Test(arguments: [
        .display("5/16\" in mm", "7.9375 mm"),
        .display("5/16 inch in mm", "7.9375 mm"),
        .display("5/16 in to cm", "0.79375 cm"),
        .display("3/8 in to mm", "9.525 mm"),
        .display("1 1/2 cups to ml", "354.8823548 mL"),
        .display("2 1/4 lb to g", "1,020.582833 g"),
        .display("5'10\" in cm", "177.8 cm"),
        .display("6′2″ to m", "1.8796 m"),
        .display("1 / 20ms to hz", "50 Hz"),
        .display("1 / 1kg", "1 kg^-1"),
        .display("5/2 - 1/2", "2"),
        .display("120 / 4 people", "30"),
        .noResult("1 1/2"),
        .noResult("5 3")
    ] as [Case])
    func aTightFractionBeforeAUnitIsOneAmount(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("4 squared", "16"),
        .display("3 cubed + 1", "28"),
        .display("(2+1) squared", "9"),
        .display("2 to the power of 10", "1,024"),
        .display("10 km to m", "10,000 m")
    ] as [Case])
    func spokenPowersAndConversions(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("$2M / 4", "500,000.00 USD"),
        .display("€1.5bn / 3", "500,000,000.00 EUR"),
        .noResult("$5mb")
    ] as [Case])
    func aMagnitudeLetterOnlyScalesMoney(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("root 4 of 81", "3"),
        .display("root 3 of -27", "-3"),
        .noResult("root 2 of -4"),
        .display("log 81 base 3", "4"),
        .display("cos(60°)", "0.5"),
        .display("2 nautical miles to km", "3.704 km"),
        .display("250 sq ft to m2", "23.22576 m²"),
        .display("3 cubic feet to l", "84.95053978 L")
    ] as [Case])
    func wordedRootsLogsAndUnits(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("60 mph * 2.5 hours", "150 mi"),
        .display("90km/h * 20min", "30 km"),
        .display("10 l/min * 30 s", "5 L"),
        .display("12 kg/day * 1 week", "84 kg")
    ] as [Case])
    func aRateOverTimeAnswersInItsNumerator(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("256 as hex", "0x100"),
        .display("10 km as m", "10,000 m"),
        .display("150 min as timespan", "2 hr 30 min")
    ] as [Case])
    func asConvertsLikeTo(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("15% on 80", "92"),
        .badges("15% on 80", source: "Expression", target: "Increased"),
        .display("25% off $60", "45.00 USD"),
        .display("90 is 10% off what", "100"),
        .display("$66 is 10% on what", "60.00 USD"),
        .display("30 as a % of 120", "25%"),
        .display("45 is what % off 50", "10%"),
        .display("66 is what % on 60", "10%"),
        .display("80 to 100 is what %", "25%"),
        .display("80 to 60 as %", "-25%"),
        .badges("80 to 100 is what %", source: "Expression", target: "Percent Change"),
        .display("0.125 as %", "12.5%"),
        .display("3/8 as percent", "37.5%"),
        .display("1/8 is what %", "12.5%"),
        .display("$30 is what % of $120", "25%"),
        .display("750 m as % of 3 km", "25%"),
        .display("half of 90", "45"),
        .display("half of $90", "45.00 USD"),
        .display("25% off $60 split 3", "15.00 USD")
    ] as [Case])
    func percentPhrasesKeepTheAmountsUnit(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("gcd of 12 and 18", "6"),
        .display("lcm of 4 and 6", "12"),
        .display("larger of 3 and 7", "7"),
        .display("smaller of 3 and 7", "3"),
        .display("midpoint between 10 and 30", "20")
    ] as [Case])
    func wordedComparisons(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("2/3 to 3 dp", "0.667"),
        .display("pi to 2 decimal places", "3.14"),
        .display("2.5 rounded", "3"),
        .display("2.5 rounded down", "2"),
        .display("2.1 rounded up", "3"),
        .display("44 to nearest 10", "40"),
        .display("44 rounded up to nearest 10", "50"),
        .display("$1,240 rounded to nearest hundred", "1,200.00 USD"),
        .badges("2.5 rounded", source: "Expression", target: "Rounded"),
        .display("0.625 as fraction", "5/8"),
        .display("6/8 as a fraction", "3/4"),
        .display("25% as fraction", "1/4"),
        .noResult("pi as fraction"),
        .badges("0.625 as fraction", source: "Expression", target: "Fraction")
    ] as [Case])
    func roundingAndFractionPhrases(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("$2,000 after 5 years at 4%", "2,433.31 USD"),
        .display("$2,000 at 4% for 5 years compounding quarterly", "2,440.38 USD"),
        .display("interest on $2,000 after 5 years at 4%", "433.31 USD"),
        .display("$2,000 for 18 months at 4%", "2,121.19 USD"),
        .display("monthly payment on $20,000 over 5 years at 6%", "386.66 USD"),
        .display("total payment on $20,000 over 5 years at 6%", "23,199.36 USD"),
        .display("monthly payment on 12000 over 1 year at 0%", "1,000"),
        .badges("$2,000 after 5 years at 4%", source: "Expression", target: "Future Value")
    ] as [Case])
    func compoundInterestAndLoans(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("2.75 hours in hours and minutes", "2 hr 45 min"),
        .display("1.5 weeks in days and hours", "10 day 12 hr"),
        .display("200 s in minutes and seconds", "3 min 20 s"),
        .noResult("5 km in hours and minutes")
    ] as [Case])
    func aDurationBreaksIntoTwoUnits(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("may 1 to may 31", "30 days").offline,
        .display("may 1 through may 31", "31 days").offline,
        .display("weeks between june 1 and june 29", "4 weeks").offline,
        .display("from 9:15 to 17:45", "8 hr 30 min").offline,
        .display("10pm to 2am", "4 hr").offline,
        .badges("10pm to 2am", source: "Friday, 24 July at 10:00 PM", target: "Saturday, 25 July at 2:00 AM").offline,
        .display("hours from 8am to 6pm", "10 hours").offline,
        .display("workdays between july 27 and august 7", "9 workdays").offline,
        .display("august 3 to august 14 in workdays", "9 workdays").offline,
        .noResult("5/2 to 1/2").offline,
        .display("2 weeks after august 3", "17 August").offline,
        .display("3 days before christmas", "22 December").offline,
        .display("weekday on 1 january 2030", "Tuesday").offline,
        .badges("weekday on 1 january 2030", source: "1 January, 2030", target: "Day of the Week").offline,
        .display("days in february 2028", "29 days").offline,
        .display("days in april", "30 days").offline,
        .display("current timestamp", "1,784,852,280").offline,
        .display("1800000000 to date", "15 January, 2027 at 8:00 AM").offline,
        .display("1800000000000 to date", "15 January, 2027 at 8:00 AM").offline
    ] as [Case])
    func aSpanBetweenTwoMoments(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }
}
