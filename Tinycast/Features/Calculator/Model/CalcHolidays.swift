import Foundation

/// Named days on one date everywhere, fixed or derived; country-specific ones stay out, as in workdays.
enum CalcHolidays {
    /// The words that mark a holiday, so the date grammar notices one without trying every name.
    static let signalWords: Set<String> = words(of: names.keys)
        .subtracting(["of", "day", "start", "end", "new", "year", "years", "eve", "good", "holy", "saint"])
        .subtracting(["sunday", "friday", "saturday", "monday", "festival", "al", "ul"])

    /// The words only a day set by moon sighting carries, so an answer can say it may move a day.
    private static let sightedWords: Set<String> = words(of: names.filter(\.value.isSighted).keys)
        .subtracting(["of", "start", "end", "al", "ul"])

    static func isHoliday(_ phrase: String) -> Bool {
        names[phrase] != nil
    }

    static func mentionsSightedDay(_ query: String) -> Bool {
        !sightedWords.isDisjoint(with: words(of: [query.lowercased()]))
    }

    private static func words(of phrases: some Sequence<String>) -> Set<String> {
        Set(phrases.flatMap { $0.split(whereSeparator: { !$0.isLetter }).map(String.init) })
    }

    /// The holiday's day in Gregorian `year`, as a start of day on `calendar`; the first if it recurs.
    static func date(_ phrase: String, year: Int, calendar: Calendar) -> Date? {
        guard let holiday = names[phrase], (1583...9999).contains(year) else { return nil }
        return holiday.date(in: year, calendar: calendar)
    }

    private enum Holiday {
        case fixed(month: Int, day: Int)
        case easter(offset: Int)
        case orthodoxEaster(offset: Int)
        case chineseNewYear(offset: Int)
        case islamic(month: Int, day: Int, offset: Int)
        case hanukkah(offset: Int)

        /// Islamic months begin at a sighted crescent, so the computed day can be a day off locally.
        var isSighted: Bool {
            if case .islamic = self { return true }
            return false
        }

        func date(in year: Int, calendar: Calendar) -> Date? {
            switch self {
            case .fixed(let month, let day):
                return CalcHolidays.day(year, month, day, calendar)
            case .easter(let offset):
                let (month, day) = CalcHolidays.gregorianEaster(year)
                return CalcHolidays.shifted(
                    CalcHolidays.day(year, month, day, calendar), by: offset, calendar)
            case .orthodoxEaster(let offset):
                let (month, day) = CalcHolidays.julianEaster(year)
                // The Julian calendar runs this many days behind the Gregorian in that century.
                let lag = year / 100 - year / 400 - 2
                return CalcHolidays.shifted(
                    CalcHolidays.day(year, month, day, calendar), by: lag + offset, calendar)
            case .chineseNewYear(let offset):
                var chinese = Calendar(identifier: .chinese)
                chinese.timeZone = calendar.timeZone
                guard let march = CalcHolidays.day(year, 3, 1, calendar),
                    let start = chinese.dateInterval(of: .year, for: march)?.start
                else { return nil }
                return CalcHolidays.shifted(calendar.startOfDay(for: start), by: offset, calendar)
            case .islamic(let month, let day, let offset):
                return CalcHolidays.islamic(
                    month: month, day: day, offset: offset, in: year, calendar: calendar)
            case .hanukkah(let offset):
                var hebrew = Calendar(identifier: .hebrew)
                hebrew.timeZone = calendar.timeZone
                // The first candle is lit on the evening of 24 Kislev, the third month from Tishri.
                guard let eve = hebrew.date(from: DateComponents(year: year + 3761, month: 3, day: 24)) else {
                    return nil
                }
                return CalcHolidays.shifted(calendar.startOfDay(for: eve), by: offset, calendar)
            }
        }
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func shifted(_ date: Date?, by days: Int, _ calendar: Calendar) -> Date? {
        date.flatMap { calendar.date(byAdding: .day, value: days, to: $0) }
    }

    private static let names: [String: Holiday] = [
        "christmas": .fixed(month: 12, day: 25), "christmas day": .fixed(month: 12, day: 25),
        "xmas": .fixed(month: 12, day: 25), "christmas eve": .fixed(month: 12, day: 24),
        "boxing day": .fixed(month: 12, day: 26),
        "new year": .fixed(month: 1, day: 1), "new years": .fixed(month: 1, day: 1),
        "new years day": .fixed(month: 1, day: 1), "new years eve": .fixed(month: 12, day: 31),
        "nye": .fixed(month: 12, day: 31),
        "halloween": .fixed(month: 10, day: 31), "valentines": .fixed(month: 2, day: 14),
        "valentines day": .fixed(month: 2, day: 14), "saint valentines day": .fixed(month: 2, day: 14),
        "orthodox christmas": .fixed(month: 1, day: 7), "orthodox christmas day": .fixed(month: 1, day: 7),
        "easter": .easter(offset: 0), "easter sunday": .easter(offset: 0),
        "good friday": .easter(offset: -2), "holy friday": .easter(offset: -2),
        "holy saturday": .easter(offset: -1), "easter saturday": .easter(offset: -1),
        "easter eve": .easter(offset: -1), "easter monday": .easter(offset: 1),
        "orthodox easter": .orthodoxEaster(offset: 0), "orthodox easter sunday": .orthodoxEaster(offset: 0),
        "orthodox pascha": .orthodoxEaster(offset: 0), "orthodox good friday": .orthodoxEaster(offset: -2),
        "chinese new year": .chineseNewYear(offset: 0), "lunar new year": .chineseNewYear(offset: 0),
        "spring festival": .chineseNewYear(offset: 0), "chinese new years eve": .chineseNewYear(offset: -1),
        "lunar new years eve": .chineseNewYear(offset: -1),
        "ramadan": .islamic(month: 9, day: 1, offset: 0),
        "ramadan start": .islamic(month: 9, day: 1, offset: 0),
        "start of ramadan": .islamic(month: 9, day: 1, offset: 0),
        "ramadan end": .islamic(month: 10, day: 1, offset: -1),
        "end of ramadan": .islamic(month: 10, day: 1, offset: -1),
        "eid al fitr": .islamic(month: 10, day: 1, offset: 0),
        "eid al-fitr": .islamic(month: 10, day: 1, offset: 0),
        "eid ul fitr": .islamic(month: 10, day: 1, offset: 0),
        "eid ul-fitr": .islamic(month: 10, day: 1, offset: 0),
        "eid-ul-fitr": .islamic(month: 10, day: 1, offset: 0),
        "eid al adha": .islamic(month: 12, day: 10, offset: 0),
        "eid al-adha": .islamic(month: 12, day: 10, offset: 0),
        "eid ul adha": .islamic(month: 12, day: 10, offset: 0),
        "eid ul-adha": .islamic(month: 12, day: 10, offset: 0),
        "eid-ul-adha": .islamic(month: 12, day: 10, offset: 0),
        "eid ul azha": .islamic(month: 12, day: 10, offset: 0),
        "eid ul-azha": .islamic(month: 12, day: 10, offset: 0),
        "eid-ul-azha": .islamic(month: 12, day: 10, offset: 0),
        "hanukkah": .hanukkah(offset: 0), "chanukah": .hanukkah(offset: 0), "hanukah": .hanukkah(offset: 0),
        "start of hanukkah": .hanukkah(offset: 0), "hanukkah start": .hanukkah(offset: 0),
        "end of hanukkah": .hanukkah(offset: 8), "hanukkah end": .hanukkah(offset: 8)
    ]

    /// The Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
    private static func gregorianEaster(_ year: Int) -> (month: Int, day: Int) {
        let a = year % 19
        let (b, c) = (year / 100, year % 100)
        let (d, e) = (b / 4, b % 4)
        let g = (b - (b + 8) / 25 + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let (i, k) = (c / 4, c % 4)
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let f = h + l - 7 * m + 114
        return (f / 31, f % 31 + 1)
    }

    /// Meeus's Julian algorithm: the Orthodox Easter date, still written in the Julian calendar.
    private static func julianEaster(_ year: Int) -> (month: Int, day: Int) {
        let a = year % 4
        let b = year % 7
        let c = year % 19
        let d = (19 * c + 15) % 30
        let e = (2 * a + 4 * b - d + 34) % 7
        let f = d + e + 114
        return (f / 31, f % 31 + 1)
    }

    /// The first time a day of the Islamic year falls in Gregorian `year`, which is eleven days longer.
    private static func islamic(month: Int, day: Int, offset: Int, in year: Int, calendar: Calendar) -> Date?
    {
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = calendar.timeZone
        guard let newYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return nil
        }
        let opening = islamic.component(.year, from: newYear)
        for islamicYear in opening...(opening + 1) {
            guard let start = islamic.date(from: DateComponents(year: islamicYear, month: month, day: day)),
                let date = shifted(calendar.startOfDay(for: start), by: offset, calendar)
            else { continue }
            if calendar.component(.year, from: date) == year { return date }
        }
        return nil
    }
}
