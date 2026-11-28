import Foundation
import Testing

@testable import Tinycast

extension CalcTests {
    @Test(
        arguments: [
            .display("time in tokyo", "9:18 AM").offline,
            .display("time in sf", "5:18 PM (yesterday)").offline,
            .display("what time is it in london", "1:18 AM").offline,
            .display("time in kolkata", "5:48 AM").offline,
            .display("time in utc", "12:18 AM").offline,
            .badges("time in tokyo", source: "UTC", target: "Tokyo").offline,
            .badges("time in sf", source: "UTC", target: "Los Angeles").offline
        ] as [Case])
    func theTimeInAZone(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("5pm london in sf", "9:00 AM").offline,
            .display("9:30am in nyc", "5:30 AM").offline,
            .display("5pm in tokyo", "2:00 AM (tomorrow)").offline,
            .badges("5pm london in sf", source: "London", target: "Los Angeles").offline
        ] as [Case])
    func aNamedSourceZoneOverridesTheMacs(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("oct 28 at 1pm et", "Wednesday, 28 October at 5:00 PM").offline,
            .display("October 28th at 1PM ET", "Wednesday, 28 October at 5:00 PM").offline,
            .display("nov 2 1pm et", "Monday, 2 November at 6:00 PM").offline,
            .display("2026-10-28 13:00 est", "Wednesday, 28 October at 5:00 PM").offline,
            .display("oct 28 1pm et in pst", "Wednesday, 28 October at 10:00 AM").offline,
            .display("oct 28 1pm new york in tokyo", "Thursday, 29 October at 2:00 AM").offline,
            .display("oct 28 1pm et + 2h", "Wednesday, 28 October at 7:00 PM").offline,
            .display("tomorrow 3pm pst", "Friday, 24 July at 10:00 PM").offline,
            .display("1pm et tomorrow", "Friday, 24 July at 5:00 PM").offline,
            .badges("oct 28 at 1pm et", source: "New York", target: "UTC").offline,
            .noResult("oct 28 at 1pm junk").offline,
            .noResult("oct 28 et").offline
        ] as [Case])
    func aDayAndClockResolveOnTheSourceZonesCalendar(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("10am utc+5", "5:00 AM").offline,
            .display("9am gmt-5 in tokyo", "11:00 PM").offline,
            .display("10am utc+5:30 in london", "5:30 AM").offline,
            .badges("10am utc+5", source: "UTC+5", target: "UTC").offline,
            .badges("10am utc+5:30 in london", source: "UTC+5:30", target: "London").offline,
            .noResult("10am utc+15").offline
        ] as [Case])
    func anAttachedOffsetNamesAZone(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("9am-5pm et in cet", "3:00 PM – 11:00 PM").offline,
            .display("9am to 5pm et in tokyo", "10:00 PM – 6:00 AM").offline,
            .display("10pm-2am london in sf", "2:00 PM – 6:00 PM").offline,
            .display("9am-5pm in tokyo", "6:00 PM – 2:00 AM").offline,
            .display("oct 28 9am-5pm et in london", "Wednesday, 28 October, 1:00 PM – 9:00 PM").offline,
            .badges("9am-5pm et in cet", source: "New York", target: "Paris").offline,
            .noResult("9am-5pm").offline,
            .noResult("9am-5pm et in new york").offline
        ] as [Case])
    func aSpanConvertsBothEnds(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("9:30 am to 5:30 pm et in cet", "3:30 PM – 11:30 PM").offline,
            .display("tomorrow at 1:30 pm et in tokyo", "Saturday, 25 July at 2:30 AM").offline,
            .display("oct 31 9pm-5am et in london", "Sunday, 1 November, 1:00 AM – 10:00 AM").offline,
            .noResult("2026-03-07 11pm-2:30am et in london").offline,
            .display("dec 31 10pm-2am et in london", "Friday, 1 January, 2027, 3:00 AM – 7:00 AM").offline,
            .noResult("2026-03-08 2:30am et in london").offline,
            .display("1pm et in london, tokyo, sydney", "6:00 PM · 2:00 AM (tomorrow) · 3:00 AM (tomorrow)")
                .offline,
            .badges("1pm et in london, tokyo, sydney", source: "New York", target: "London · Tokyo · Sydney")
                .offline,
            .copy("1pm et in london, tokyo, sydney", "London 6:00 PM, Tokyo 2:00 AM, Sydney 3:00 AM").offline,
            .display("time in london, tokyo and sydney", "1:18 AM · 9:18 AM · 10:18 AM").offline,
            .noResult("1pm et in london, nowhere").offline
        ] as [Case])
    func overnightSpansAndListsShareOneCard(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("time in tokyo", "09:18").offline.withLocale("en_US@hours=h23"),
            .display("5pm in tokyo", "02:00 (tomorrow)").offline.withLocale("en_US@hours=h23"),
            .display("unix -1", "31 December, 1969 at 23:59:59").offline.withLocale("en_US@hours=h23"),
            .display("now + 90 min", "24 July at 01:48").offline.withLocale("en_US@hours=h23"),
            .display("time in sf", "17:18 (yesterday)").offline.withLocale("en_GB"),
            .badges("hrs till 9am", source: "00:18", target: "09:00").offline.withLocale("en_GB"),
            .display("time in sf", "5:18 pm (yesterday)").offline.withLocale("en_GB@hours=h12")
        ] as [Case])
    func theClockFollowsTheLocalesHourCycle(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("5:30 pm to London", "6:30 PM").offline,
            .display("5 pm in Tokyo", "2:00 AM (tomorrow)").offline,
            .display("5:30 am SF to London", "1:30 PM").offline,
            .display("12 am SF to London", "8:00 AM").offline,
            .display("12 pm SF to London", "8:00 PM").offline,
            .display("5:30 pm in SF to London + 30 min", "2:00 AM (tomorrow)").offline,
            .copy("5:30 pm SF to London", "1:30 AM"),
            .noResult("13 pm SF to London").offline,
            .noResult("5:60 pm SF to London").offline,
            .display("5:30 pm SF + 30 min", "1:00 AM (tomorrow)").offline.at(septemberNoon),
            .display("5:30pm SF - 2h", "10:30 PM").offline.at(septemberNoon),
            .display("5:30pm in SF", "10:30 AM").offline.at(septemberNoon),
            .display("5:30pm SF to London", "1:30 AM (tomorrow)").offline.at(septemberNoon),
            .noResult("2:30 am SF").offline.at("2026-03-08T12:00:00Z")
        ] as [Case])
    func aClockAtAPlaceConvertsToTheMacsZone(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("time in nyc", "8:18 PM (yesterday)").offline,
            .display("time in cet", "2:18 AM").offline,
            .display("1 cup to ml", "236.5882365 mL"),
            .noResult("time in xyzzy"),
            .noResult("in tokyo")
        ] as [Case])
    func aliasesCoverWhatIdentifiersDoNotSpell(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("time in vie", "2:18 AM").offline,
            .display("time in lhr", "1:18 AM").offline,
            .display("time in nrt", "9:18 AM").offline,
            .display("time in sfo", "5:18 PM (yesterday)").offline,
            .badges("time in vie", source: "UTC", target: "Vienna").offline,
            .display("5pm vie in nrt", "12:00 AM (tomorrow)").offline,
            .error("10 mad to usd", "No exchange rate for MAD."),
            .badges("time in ist", source: "UTC", target: "Kolkata").offline
        ] as [Case])
    func airportCodesNameZones(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("5pm london in sf", "9:00 AM").offline,
            .display("5pm london in sf + 2h", "11:00 AM").offline,
            .display("5pm london in sf - 1 hour", "8:00 AM").offline,
            .display("5pm london in sf + 30 min", "9:30 AM").offline,
            .badges("5pm london in sf + 2h", source: "London", target: "Los Angeles").offline,
            .display("1 cup to ml", "236.5882365 mL"),
            .noResult("5pm london in sf + 2 kg")
        ] as [Case])
    func aTrailingOffsetShiftsAZoneAnswer(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .badges("23:30 Pago Pago to Kiritimati", source: "Pago Pago", target: "Kiritimati").offline,
            .badges("00:30 Kiritimati to Pago Pago", source: "Kiritimati", target: "Pago Pago").offline,
            .copy("23:30 Pago Pago to Kiritimati", "12:30 AM"),
            .copy("00:30 Kiritimati to Pago Pago", "11:30 PM"),
            .display("23:30 Pago Pago to Kiritimati + 30 min", "1:00 AM (tomorrow)").offline,
            .display("00:30 Kiritimati to Pago Pago + 30 min", "12:00 AM (yesterday)").offline
        ] as [Case])
    func crossingTheDateLineMovesTheDay(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("diff paris", "2:18 AM (+2h)").offline,
            .display("time diff tokyo", "9:18 AM (+9h)").offline,
            .display("diff kolkata", "5:48 AM (+5h 30m)").offline,
            .badges("diff paris", source: "UTC", target: "Paris").offline,
            .noResult("diff xyzzy")
        ] as [Case])
    func aZoneDifferenceCarriesTheOffset(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("time in 4 hours", "4:18 AM").offline,
            .display("time in 90 min", "1:48 AM").offline,
            .display("time in 4 hours in san francisco", "9:18 PM (yesterday)").offline,
            .display("time in 4 hours in sf", "9:18 PM (yesterday)").offline,
            .badges("time in 4 hours in sf", source: "UTC", target: "Los Angeles").offline,
            .display("time in tokyo + 2", "11:18 AM").offline,
            .display("time in tokyo - 2", "7:18 AM (tomorrow)").offline,
            .display("5pm london in sf + 3", "12:00 PM").offline,
            .noResult("time in 4").offline,
            .display("5 + 3", "8")
        ] as [Case])
    func aBareOffsetOnAClockIsHours(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("time\u{a0}in\u{a0}tokyo", "9:18 AM").offline,
            .display("time\u{9}in\u{9}tokyo", "9:18 AM").offline,
            .display("time\u{2009}in\u{2009}tokyo", "9:18 AM").offline
        ] as [Case])
    func anyWhitespaceSeparatesTheWords(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("time in são paulo", "9:18 PM (yesterday)").offline,
            .display("time in sao paulo", "9:18 PM (yesterday)").offline,
            .display("time in zürich", "2:18 AM").offline
        ] as [Case])
    func accentedPlaceNamesResolve(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .badges("time in graz", source: "UTC", target: "Vienna").offline,
            .badges("time in salzburg", source: "UTC", target: "Vienna").offline,
            .badges("time in klagenfurt", source: "UTC", target: "Vienna").offline,
            .badges("time in hannover", source: "UTC", target: "Berlin").offline,
            .badges("time in stuttgart", source: "UTC", target: "Berlin").offline,
            .badges("time in basel", source: "UTC", target: "Zurich").offline,
            .badges("time in manchester", source: "UTC", target: "London").offline,
            .badges("time in florence", source: "UTC", target: "Rome").offline,
            .badges("time in lyon", source: "UTC", target: "Paris").offline,
            .badges("time in krakow", source: "UTC", target: "Warsaw").offline,
            .badges("time in düsseldorf", source: "UTC", target: "Berlin").offline,
            .badges("time in kraków", source: "UTC", target: "Warsaw").offline,
            .badges("time in malmö", source: "UTC", target: "Stockholm").offline,
            .badges("5pm graz in basel", source: "Vienna", target: "Zurich").offline
        ] as [Case])
    func aCityTakesItsZonesClock(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("time in uk", "1:18 AM").offline,
            .display("Time in UK", "1:18 AM").offline,
            .badges("time in united kingdom", source: "UTC", target: "London").offline,
            .badges("time in japan", source: "UTC", target: "Tokyo").offline,
            .badges("what time is it in germany", source: "UTC", target: "Berlin").offline,
            .badges("time in côte d’ivoire", source: "UTC", target: "Abidjan").offline,
            .badges("time in trinidad and tobago", source: "UTC", target: "Port of Spain").offline,
            .display("5pm uk in japan", "1:00 AM (tomorrow)").offline,
            .display("time in uk + 2", "3:18 AM").offline,
            .badges("time in usa", source: "UTC", target: "New York").offline,
            .badges("time in us", source: "UTC", target: "New York").offline,
            .badges("time in australia", source: "UTC", target: "Sydney").offline,
            .badges("time in canada", source: "UTC", target: "Toronto").offline,
            .badges("time in russia", source: "UTC", target: "Moscow").offline,
            .badges("time in uae", source: "UTC", target: "Dubai").offline,
            .display("10 ms to us", "10,000 µs"),
            .noResult("time in antarctica").offline
        ] as [Case])
    func aCountryAnswersWithItsMainClock(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("SF time", "5:18 PM (yesterday)").offline,
            .display("time SF", "5:18 PM (yesterday)").offline,
            .display("current time to Tokyo", "9:18 AM").offline,
            .display("what time is it to Tokyo", "9:18 AM").offline,
            .display("Tokyo time", "9:18 AM").offline,
            .display("  sF\tTiMe  ", "5:18 PM (yesterday)").offline,
            .display("San\u{a0}Francisco\u{2009}time", "5:18 PM (yesterday)").offline,
            .display("Tokyo\ntime", "9:18 AM").offline,
            .display("  TiMe\tSF  ", "5:18 PM (yesterday)").offline,
            .display("SF\u{a0}TiMe\u{2009}ZoNe", "5:18 PM (yesterday)").offline,
            .display("TimeZone\nIn\tTokyo", "9:18 AM").offline,
            .display("Canada\tTiMe\u{a0}ZoNe\tTo\nChina", "8:00 PM").offline.at(septemberNoon)
        ] as [Case])
    func zoneWordsIgnoreCaseAndWhitespace(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    // MARK: Whatever the Mac's own zone

    /// Where the Mac is, and when the query is asked.
    struct Home: Sendable, CustomTestStringConvertible {
        let zone: String
        let now: String

        var testDescription: String { "\(zone) at \(now)" }

        static func every(_ zones: [String] = CalcTests.homeZones, at nows: [String]) -> [Home] {
            nows.flatMap { now in zones.map { Home(zone: $0, now: now) } }
        }
    }

    @Test(
        arguments: homeZones,
        [
            "5:30pm SF to London", "5:30 pm SF to London", "5:30 pm in SF to London",
            "5:30 PM in San Francisco to London", "5:30\u{a0}pm SF to London",
            "5:30 pm SF in London", "5:30 pm SF at London", "5:30 pm at SF to London",
            "17:30 SF to London"
        ])
    func aClockAtANamedPlaceConvertsToAnother(_ home: String, _ query: String) throws {
        let display = Case.display(query, "1:30 AM (tomorrow)").offline.at(Self.septemberNoon).inZone(home)
        let badges = Case.badges(query, source: "Los Angeles", target: "London")
            .offline.at(Self.septemberNoon).inZone(home)
        #expect(try display.actual() == display.expected)
        #expect(try badges.actual() == badges.expected)
    }

    @Test(arguments: homeZones, ["5pm SF to London", "5pm in SF to London", "5 pm in SF to London"])
    func anHourAtANamedPlaceConvertsToAnother(_ home: String, _ query: String) throws {
        let row = Case.display(query, "1:00 AM (tomorrow)").offline.at(Self.septemberNoon).inZone(home)
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: homeZones,
        [
            "5pm PSTT to London", "5:30 pm PSTT to London", "5pm in PSTT to London",
            "5pm SF junk to London", "5pm in to London", "5pm at to London",
            "5pm pm SF to London", "5pm am SF to London",
            "time in sf in 4 hours", "now in tokyo in 2h",
            "time at sf in 4 hours", "now at tokyo in 2h"
        ])
    func aClockAtAnUnknownPlaceHasNoResult(_ home: String, _ query: String) throws {
        #expect(try Self.evaluate(query, at: Self.septemberNoon, zone: home) == nil)
    }

    /// A source clock with no target converts to wherever the Mac is.
    struct LocalConversion: Sendable, CustomTestStringConvertible {
        let zone: String
        let target: String
        let time: String
        let dayNote: String

        var testDescription: String { zone }
    }

    @Test(
        arguments: [
            LocalConversion(
                zone: "Asia/Shanghai", target: "Shanghai", time: "8:30 AM", dayNote: " (tomorrow)"),
            LocalConversion(zone: "UTC", target: "UTC", time: "12:30 AM", dayNote: " (tomorrow)"),
            LocalConversion(zone: "America/Los_Angeles", target: "Los Angeles", time: "5:30 PM", dayNote: "")
        ], ["5:30pm SF", "5:30 pm SF", "17:30 San Francisco", "5:30 PM SFO", "  5:30\tpm\u{00A0}sf  "])
    func aClockAtAPlaceAloneConvertsToTheMacsZone(_ home: LocalConversion, _ query: String) throws {
        let expected = CalcResult(
            expression: "5:30 PM", sourceBadge: "Los Angeles", targetBadge: home.target,
            payload: .value(display: home.time + home.dayNote, copyText: home.time), canChain: false)
        #expect(try Self.evaluate(query, at: Self.septemberNoon, zone: home.zone) == expected)
    }

    static let datelineDestinations = [
        "UTC": "UTC", "Asia/Shanghai": "Shanghai", "Pacific/Kiritimati": "Kiritimati",
        "Pacific/Pago_Pago": "Pago Pago"
    ]
    static let datelineHomes = Home.every(
        ["UTC", "Asia/Shanghai", "Pacific/Kiritimati", "Pacific/Pago_Pago"],
        at: ["2026-09-15T12:00:00Z", "2026-01-01T00:00:00Z", "2026-11-01T12:00:00Z"])

    @Test(
        arguments: datelineHomes,
        [
            ("5 pm SF", "5pm SF"), ("12 am Canada", "12am Canada"),
            ("12 pm CDG", "12pm CDG"), ("09:15 Kathmandu", "09:15 Kathmandu"),
            ("23:30 Pago Pago", "23:30 Pago Pago"), ("00:30 Kiritimati", "00:30 Kiritimati"),
            ("1:30 am SF", "1:30am SF"), ("17:30 São Paulo", "17:30 São Paulo")
        ])
    func aClockAtAPlaceAloneMatchesTheExplicitConversion(
        _ home: Home, _ pair: (query: String, explicit: String)
    )
        throws
    {
        let destination = try #require(Self.datelineDestinations[home.zone])
        let explicit = try #require(
            try Self.evaluate("\(pair.explicit) to \(destination)", at: home.now, zone: home.zone))
        #expect(try Self.evaluate(pair.query, at: home.now, zone: home.zone) == explicit)
    }

    @Test(
        arguments: Home.every(at: [
            "2026-09-15T12:00:00Z", "2026-09-30T12:00:00Z", "2026-12-31T12:00:00Z",
            "2026-03-08T12:00:00Z", "2026-11-01T12:00:00Z"
        ]),
        [
            ("23:30 Pago Pago to Kiritimati", "12:30 AM (in 2 days)"),
            ("00:30 Kiritimati to Pago Pago", "11:30 PM (2 days ago)"),
            ("22:59 Pago Pago to Kiritimati", "11:59 PM (tomorrow)"),
            ("01:00 Kiritimati to Pago Pago", "12:00 AM (yesterday)"),
            ("12:00 Pago Pago to Pago Pago", "12:00 PM")
        ])
    func theDayNoteCountsWholeDaysAcrossTheDateLine(
        _ home: Home, _ pair: (query: String, display: String)
    )
        throws
    {
        let row = Case.display(pair.query, pair.display).offline.at(home.now).inZone(home.zone)
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        "5:30 pm PSTT", "5:30pm PSTT", "5:30pm SF junk", "5:30 pm SF London",
        "5pm", "5 pm", "17:30", "17:30 pm", "5 SF", "pm SF", "now SF",
        "13pm SF", "5:60pm SF", "5pm pm SF", "5:30 am pm SF", "25:30 SF",
        "5:30pm SF to", "5:30pm SF to PSTT", "5:30pm SF + 2 kg",
        "time in sf in 4 hours", "now in tokyo in 2h", "Screen Time", "Safari SF"
    ])
    func aClockWithoutAKnownPlaceHasNoResult(_ query: String) throws {
        #expect(try Self.evaluate(query) == nil)
    }

    // MARK: Zone phrasings

    @Test func countryZonesAreRealIdentifiers() {
        let unresolved = CountryZoneData.zones.values.filter { TimeZone(identifier: $0) == nil }
        #expect(unresolved.isEmpty)
    }

    @Test func nowInACountryIsItsMainClock() throws {
        let expected = CalcResult(
            expression: "12:00 PM", sourceBadge: "UTC", targetBadge: "New York",
            payload: .value(display: "8:00 AM", copyText: "8:00 AM"), canChain: false)
        #expect(try Self.evaluate("now in usa", at: Self.septemberNoon) == expected)
    }

    @Test(arguments: ["Canada timezone", "Canada time zone", "timezone Canada", "timezone in Canada"])
    func aCountrysTimezoneIsItsMainClock(_ query: String) throws {
        let expected = CalcResult(
            expression: "12:00 PM", sourceBadge: "UTC", targetBadge: "Toronto",
            payload: .value(display: "8:00 AM", copyText: "8:00 AM"), canChain: false)
        #expect(try Self.evaluate(query, at: Self.septemberNoon) == expected)
    }

    @Test(arguments: ["Canada time to China", "Canada timezone to China", "Canada time zone to China"])
    func aCountrysTimeConvertsToAnother(_ query: String) throws {
        let expected = CalcResult(
            expression: "8:00 AM", sourceBadge: "Toronto", targetBadge: "Shanghai",
            payload: .value(display: "8:00 PM", copyText: "8:00 PM"), canChain: false)
        #expect(try Self.evaluate(query, at: Self.septemberNoon) == expected)
    }

    static let phrasedHomes = Home.every(
        at: ["2026-01-15T12:00:00Z", "2026-09-15T12:00:00Z", "2026-09-15T23:30:00Z"])

    @Test(
        arguments: phrasedHomes,
        [
            "SF", "Tokyo", "London", "Shanghai", "San Francisco", "New York", "Canada",
            "USA", "United States", "United Kingdom", "India", "South Korea", "PST", "UTC", "GMT",
            "SFO", "CDG", "LDN", "SÃO PAULO", "Zürich", "Côte d’Ivoire", "Trinidad and Tobago",
            "Georgia", "Basel", "The Hague", "Swift Current"
        ])
    func everyPhrasingOfAPlacesTimeAnswersAlike(_ home: Home, _ place: String) throws {
        let expected = try #require(try Self.evaluate("time in \(place)", at: home.now, zone: home.zone))
        for query in [
            "\(place) TiMe", "time \(place)", "\(place) timezone", "\(place) time zone",
            "timezone \(place)", "timezone in \(place)", "now in \(place)"
        ] {
            #expect(try Self.evaluate(query, at: home.now, zone: home.zone) == expected, "\(query)")
        }
    }

    @Test(
        arguments: phrasedHomes,
        [
            ("Canada", "China"), ("SFO", "CDG"), ("Tokyo", "SF"), ("SF", "Tokyo"),
            ("New York", "São Paulo"), ("Kolkata", "Kathmandu"), ("Kiritimati", "Pago Pago")
        ])
    func everyPhrasingOfAConversionAnswersAlike(
        _ home: Home, _ places: (source: String, target: String)
    )
        throws
    {
        let expected = try #require(
            try Self.evaluate("time \(places.source) to \(places.target)", at: home.now, zone: home.zone))
        for phrase in ["time", "timezone", "time zone"] {
            let query = "\(places.source) \(phrase) to \(places.target)"
            #expect(try Self.evaluate(query, at: home.now, zone: home.zone) == expected, "\(query)")
        }
    }

    @Test(arguments: [
        "Screen Time", "QuickTime Player", "Time Machine", "FaceTime", "PSTT time", "xyzzy time",
        "SF junk time", "4 hours time", "90 min time", "5pm time", "5pm SF time",
        "SF current time", "SF time now", "SF time + 2h", "time in SF time", "time time"
    ])
    func aTimeWordAfterAnythingButAPlaceHasNoResult(_ query: String) throws {
        #expect(try Self.evaluate(query) == nil)
    }

    static let nonPlaces = ["PSTT", "xyzzy", "SF junk", "4 hours", "5pm SF", "time"]
    static let zonePhrasingsAroundNonPlaces = nonPlaces.flatMap { place in
        [
            "time \(place)", "\(place) timezone", "\(place) time zone",
            "timezone \(place)", "timezone in \(place)", "\(place) time to China",
            "\(place) timezone to China", "Canada time zone to \(place)"
        ]
    }

    @Test(arguments: zonePhrasingsAroundNonPlaces)
    func aZonePhrasingAroundANonPlaceHasNoResult(_ query: String) throws {
        #expect(try Self.evaluate(query) == nil)
    }

    @Test(arguments: [
        "timezone", "time zone", "timezone in", "timezone in in SF", "timezone to China",
        "timezone settings", "SF timezone app", "Canada time to",
        "Canada time to China to Tokyo", "time in SF in 4 hours", "now in usa in 2h",
        "Canada timezone to 2h", "timezone in 4 hours", "Canada time to China + 2h"
    ])
    func anIncompleteOrOverlongZonePhrasingHasNoResult(_ query: String) throws {
        #expect(try Self.evaluate(query) == nil)
    }
}
