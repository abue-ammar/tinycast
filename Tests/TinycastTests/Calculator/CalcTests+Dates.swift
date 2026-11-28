import Testing

@testable import Tinycast

extension CalcTests {
    @Test(arguments: [
        .display("hrs till 9am", "8.7 hours").offline,
        .badges("hrs till 9am", source: "12:18 AM", target: "9:00 AM").offline,
        .display("hrs till july", "8,207.7 hours").offline,
        .badges("hrs till july", source: "12:18 AM", target: "12:00 AM").offline,
        .display("days till 9april", "259 days").offline,
        .badges("days till 9april", source: "Friday, 24 July", target: "Friday, 9 April, 2027").offline,
        .display("days till july", "342 days").offline,
        .badges("days till july", source: "Friday, 24 July", target: "Thursday, 1 July, 2027").offline,
        .display("days until tomorrow", "1 day").offline
    ] as [Case])
    func aCountdownToAMoment(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("days until 29th of october", "97 days").offline,
        .display("days until the 29th of october", "97 days").offline,
        .display("days until 29.10", "97 days").offline,
        .display("days until 29.10.", "97 days").offline,
        .display("days until 29/10", "97 days").offline,
        .display("days until 10/29", "97 days").offline,
        .display("days since 20.7", "4 days").offline,
        .display("october 28th", "28 October").offline,
        .display("29th of october", "29 October").offline,
        .display("oct 28th at 1pm", "28 October at 1:00 PM").offline,
        .noResult("29.10").offline,
        .noResult("5th").offline
    ] as [Case])
    func ordinalsAndADayMonthAfterUntilAreDates(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("in 3 days", "27 July").offline,
        .display("in 2 weeks", "7 August").offline,
        .display("in 90 min", "24 July at 1:48 AM").offline,
        .noResult("in 5 cm").offline,
        .display("10 in in cm", "25.4 cm").offline,
        .display("next week", "31 July").offline,
        .display("last month", "24 June").offline,
        .display("next year", "24 July, 2027").offline,
        .display("days until next week", "7 days").offline,
        .display("end of month", "31 July").offline,
        .display("start of the month", "1 July").offline,
        .display("end of next month", "31 August").offline,
        .display("beginning of year", "1 January").offline,
        .display("end of year", "31 December").offline,
        .display("days until end of month", "7 days").offline,
        .noResult("end of week").offline
    ] as [Case])
    func relativeAndBoundaryDates(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("days until christmas", "154 days").offline,
        .display("days until new years eve", "160 days").offline,
        .display("days until valentine's day", "205 days").offline,
        .display("days since halloween", "266 days").offline,
        .display("christmas + 3 days", "28 December").offline,
        .noResult("christmas").offline,
        .noResult("easter").offline,
        .display("new years eve + 3 days", "3 January, 2027").offline,
        .display("new year's eve + 3 days", "3 January, 2027").offline,
        .display("valentines day + 3 days", "17 February").offline,
        .display("valentine's day + 3 days", "17 February").offline,
        .display("valentine’s day + 3 days", "17 February").offline,
        .display("hrs till christmas at 9am", "8,757 hours").offline.at("2026-12-25T12:00:00Z"),
        .noResult("new york").offline
    ] as [Case])
    func fixedDateOccasions(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("week number", "30").offline,
        .display("what week is it", "30").offline,
        .display("week number of christmas", "52").offline,
        .display("day of year", "205").offline,
        .display("day of the year for dec 31", "365").offline,
        .badges("week number", source: "Friday, 24 July, 2026", target: "Week of the Year").offline,
        .display("age 1990-05-03", "36 years").offline,
        .display("born 3 may 1990", "36 years").offline,
        .display("age 1990-08-03", "35 years").offline,
        .noResult("age 3 may").offline,
        .noResult("age 2030-01-01").offline,
        .noResult("ages ago").offline,
        .display("weeks till 9april", "37 weeks").offline,
        .display("today + 3 weeks", "14 August").offline,
        .display("now + 90 min", "24 July at 1:48 AM").offline,
        .display("jul 4 - today", "345 days").offline,
        .badges("jul 4 - today", source: "Sunday, 4 July, 2027", target: "Friday, 24 July").offline
    ] as [Case])
    func factsAboutADate(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10 - 3", "7").offline,
        .display("450 + 20%", "540").offline,
        .display("5/2 - 1/2", "2").offline,
        .display("3/4 - 1/4", "0.5").offline,
        .display("1/2 - 1/4", "0.25").offline,
        .display("9/4 - today", "42 days").offline,
        .display("today - 9/4", "-42 days").offline,
        .display("today - 1.1.2026 + 3", "207 days").offline,
        .display("today - 1.1.2026 + 1 week - 1", "210 days").offline,
        .display("(today - 1.1.2026 + 3) / 2", "103.5 day").offline,
        .display("(15:00 - 9:30) / 2", "2.75 hr").offline,
        .display("week 44 2026", "Sun, 25 Oct – Sat, 31 Oct, 2026").offline,
        .display("week 1", "Sun, 28 Dec – Sat, 3 Jan, 2026").offline,
        .noResult("week 54 2026").offline
    ] as [Case])
    func plainMathIsNotDateMath(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("today", "24 July").offline,
        .display("tomorrow", "25 July").offline,
        .display("yesterday", "23 July").offline,
        .display("now", "24 July at 12:18 AM").offline,
        .badges("tomorrow", source: "Friday, 24 July", target: "Saturday").offline,
        .expression("Today", "Today"),
        .display("time", "12:18 AM").offline,
        .badges("time", source: "Friday, 24 July", target: "UTC").offline,
        .noResult("july").offline,
        .noResult("monday").offline,
        .noResult("noon").offline,
        .noResult("todays").offline,
        .noResult("times").offline
    ] as [Case])
    func aLoneWordNamingOneMomentAnswers(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("days since 9jul", "15 days").offline,
        .badges("days since 9jul", source: "Thursday, 9 July", target: "Friday, 24 July").offline,
        .display("weeks since 3jul", "3 weeks").offline,
        .display("days since yesterday", "1 day").offline,
        .badges("today + 3 weeks", source: "Friday, 24 July", target: "Friday").offline
    ] as [Case])
    func daysSinceAPastDate(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("1970-01-01T00:00:00Z to unix", "0").offline,
        .display("1970-01-01T01:00:00+01:00 to unix", "0").offline,
        .display("1970-01-01T00:00:00.125Z to unix ms", "125").offline,
        .display("1970-01-01T00:00:00.002Z to unix ms", "2").offline,
        .display("1969-12-31T23:59:59.999Z to unix ms", "-1").offline,
        .display("unix 1234567890.125 to unix ms", "1,234,567,890,125").offline,
        .display("1970-01-01T00:00:00Z + 1h to unix", "3,600").offline,
        .display("unix 0 to date", "1 January, 1970 at 12:00 AM").offline,
        .display("1970-01-01T00:00:00Z to date", "1 January, 1970 at 12:00 AM").offline,
        .display("1000 unix ms", "1 January, 1970 at 12:00:01 AM").offline,
        .display("unix -1", "31 December, 1969 at 11:59:59 PM").offline,
        .display("2026-07-24T07:30:00+02:00 + 30min", "24 July at 6:00 AM").offline,
        .noResult("2026-02-30T00:00:00Z").offline,
        .noResult("2026-07-24T00:00:00Z junk").offline,
        .noResult("unix 1e30").offline
    ] as [Case])
    func isoAndUnixTimestamps(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("monday in 3 weeks", "10 August").offline,
        .display("monday in 1 week", "27 July").offline,
        .display("tuesday in 2 weeks", "4 August").offline,
        .display("friday in 2 weeks", "7 August").offline,
        .badges("monday in 3 weeks", source: "Friday, 24 July", target: "Monday").offline,
        .noResult("monday in 3 kg"),
        .display("10 in in cm", "25.4 cm")
    ] as [Case])
    func aWeekdayInSomeWeeks(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("19.2.27 + 3", "22 February, 2027").offline,
        .display("19.02.2027 + 3", "22 February, 2027").offline,
        .display("19.2.27 - 3", "16 February, 2027").offline,
        .display("31.12.26 + 1", "1 January, 2027").offline,
        .display("19.2.27 + 3 weeks", "12 March, 2027").offline,
        .badges("19.2.27 + 3", source: "Friday, 19 February, 2027", target: "Monday").offline,
        .display("1.5 + 3", "4.5"),
        .display("99.99 + 0.01", "100"),
        .noResult("1.2.3 + 1").offline,
        .noResult("1.5.5 + 3").offline,
        .noResult("30.2.27 + 1").offline
    ] as [Case])
    func dottedDatesAreDayFirst(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("28. aug + 3", "31 August").offline,
        .display("28. august + 3", "31 August").offline,
        .display("28.aug + 3", "31 August").offline,
        .display("1. jan + 1", "2 January").offline,
        .display("28. aug 2027 + 3", "31 August, 2027").offline,
        .badges("28. aug + 3", source: "Friday, 28 August", target: "Monday").offline,
        .noResult("28.5 aug + 1").offline
    ] as [Case])
    func anOrdinalDotMarksADay(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("25. aug", "25 August").offline,
        .display("25 aug", "25 August").offline,
        .display("aug 25", "25 August").offline,
        .display("25.8.27", "25 August, 2027").offline,
        .display("1. jan", "1 January").offline,
        .badges("25. aug", source: "Friday, 24 July", target: "Tuesday").offline,
        .display("25. aug + 3", "28 August").offline,
        .noResult("july").offline,
        .noResult("aug").offline
    ] as [Case])
    func aWrittenDayAnswersWithItsWeekday(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("17.2.26 + 100 week days - 4 + 2", "5 July").offline,
        .display("17.2.26 + 100 weekdays", "7 July").offline,
        .display("17.2.26 + 100 weekdays - 4", "3 July").offline,
        .display("today + 3 weeks - 2 days", "12 August").offline,
        .display("today + 5 + 2", "31 July").offline,
        .display("today + 1 day + 1 day + 1 day", "27 July").offline,
        .display("now + 90 min + 30 min", "24 July at 2:18 AM").offline,
        .display("3:45pm + 5 - 2", "24 July at 6:45 PM").offline,
        .badges("17.2.26 + 100 week days - 4 + 2", source: "Tuesday, 17 February", target: "Sunday").offline,
        .noResult("today + 3 weeks - kg").offline,
        .noResult("today + 5 - abc").offline,
        .display("jul 4 - today", "345 days").offline,
        .display("5 + 3 - 2", "6"),
        .display("5/2 - 1/2", "2")
    ] as [Case])
    func dateArithmeticChainsLeftToRight(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("3:45pm + 5", "24 July at 8:45 PM").offline,
        .display("3:45pm - 2", "24 July at 1:45 PM").offline,
        .display("august 5 + 5", "10 August").offline,
        .display("august 5 - 5", "31 July").offline
    ] as [Case])
    func aBareNumberTakesTheMomentsUnit(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("tomorrow at 9am", "25 July at 9:00 AM").offline,
        .display("next monday", "27 July").offline,
        .display("last friday", "17 July").offline,
        .badges("tomorrow at 9am", source: "Friday, 24 July", target: "Saturday").offline,
        .display("next monday at 7:30 + 5", "27 July at 12:30 PM").offline,
        .display("next monday at 7:30 + 1 day 2h 15min - 1", "28 July at 8:45 AM").offline,
        .display("tomorrow at 23:30 + 1.5 hours", "26 July at 1:00 AM").offline,
        .display("3 days from next monday at 7:30", "30 July at 7:30 AM").offline,
        .display("1h 30min ago", "23 July at 10:48 PM").offline,
        .display("31.1.26 at 7:30 + 1 month", "28 February at 7:30 AM").offline,
        .display("29.2.24 + 1 year", "28 February, 2025").offline,
        .display("today + 1 year 2 months - 1 day", "23 September, 2027").offline,
        .display("1. jan + 1 + 1", "3 January").offline,
        .display("hours till tomorrow at 7:30", "31.2 hours").offline,
        .display("hours since yesterday at noon", "12.3 hours").offline,
        .display("hours till friday at midnight", "167.7 hours").offline,
        .display("hours since friday at midnight", "0.3 hours").offline,
        .display("hours till jul 24 at midnight", "8,759.7 hours").offline,
        .display("next monday at 9:30 - next monday at 7:00", "2 hr 30 min").offline,
        .display("next monday at 9:30 - next monday at 7:00 to minutes", "150 min").offline,
        .display("2026-08-01 - 2026-07-24", "8 days").offline,
        .display("today at 9:30 - today at 7:00 to hours", "2.5 hr").offline,
        .display("now + 5 seconds", "24 July at 12:18:05 AM").offline,
        .display("next\u{a0}monday at\t7:30 + 5", "27 July at 12:30 PM").offline,
        .display("tomorrow - 5 weekdays", "20 July").offline,
        .display("today + 10000 weekdays", "21 November, 2064").offline
    ] as [Case])
    func aNamedMomentCarriesATimeOrQualifier(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("2026-03-28 at 7:30 + 1 day", "29 March at 7:30 AM").offline.inZone("Europe/Vienna"),
        .display("2026-03-28 at 7:30 + 24 hours", "29 March at 8:30 AM").offline.inZone("Europe/Vienna"),
        .display("2026-03-29 at 7:30 - 2026-03-28 at 7:30 to hours", "23 hr").offline.inZone("Europe/Vienna"),
        .display("2026-10-24 at 7:30 + 1 day", "25 October at 7:30 AM").offline.inZone("Europe/Vienna"),
        .display("2026-10-25 at 7:30 - 2026-10-24 at 7:30 to hours", "25 hr").offline.inZone("Europe/Vienna"),
        .display("1:00 - 3:00", "-2 hr").offline.inZone("Europe/Vienna"),
        .noResult("2:30am vienna in london").offline.at("2026-03-29T00:00:00Z").inZone("Europe/Vienna")
    ] as [Case])
    func daylightSavingFollowsTheCalendar(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("today + 1 business day", "27 July").offline,
        .display("today + 5 business days", "31 July").offline,
        .display("today - 1 business day", "23 July").offline,
        .display("today - 3 business days", "21 July").offline,
        .display("tomorrow + 10 work days", "7 August").offline,
        .display("today + 15 workdays", "14 August").offline,
        .display("today + 5 weekdays", "31 July").offline,
        .badges("today + 5 business days", source: "Friday, 24 July", target: "Friday").offline,
        .badges("today + 1 business day", source: "Friday, 24 July", target: "Monday").offline,
        .display("5 weekdays from now", "31 July").offline,
        .display("10 business days from today", "7 August").offline,
        .display("3 days from today", "27 July").offline,
        .display("2 weeks ago", "10 July").offline,
        .display("3 days ago", "21 July").offline,
        .badges("5 weekdays from now", source: "Friday, 24 July", target: "Friday").offline,
        .display("august 26 2026 + 15 workdays", "16 September").offline,
        .display("august 26 2026 + 15 days", "10 September").offline,
        .display("26 august 2026 + 1 day", "27 August").offline,
        .display("august 26 2027 + 1 day", "27 August, 2027").offline,
        .display("55h in workdays", "6.875 workdays"),
        .display("3 workdays in hours", "24 hr"),
        .noResult("5 from 10")
    ] as [Case])
    func businessDaysSkipWeekends(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        "tomorrow at 7:99", "tomorrow at 7::30", "today + 1.5 months",
        "today + 1h 30", "today + -9223372036854775808 weekdays", "today + 9223372036854775807 weeks"
    ])
    func aMalformedMomentHasNoResult(_ query: String) throws {
        #expect(try Self.evaluate(query) == nil)
    }
}
