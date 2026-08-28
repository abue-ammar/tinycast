import Foundation

/// Clock time in another city. See docs/features/calculator.md.
enum CalcTimeZone {
    static func evaluate(_ raw: String, now: Date, calendar: Calendar) -> CalcResult? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty, query.count <= 128 else { return nil }

        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return nil }

        // Every grammar needs a connector, so an app search never touches the zone table.
        guard let connector = words.lastIndex(where: { $0 == "in" || $0 == "to" || $0 == "at" })
        else { return nil }
        let targetWords = Array(words[(connector + 1)...])
        guard !targetWords.isEmpty, let target = zone(named: targetWords) else { return nil }

        let leading = Array(words[0..<connector])
        guard let source = sourceMoment(leading, now: now, calendar: calendar) else { return nil }

        var display = calendar
        display.timeZone = target
        let sameDay =
            calendar.dateComponents(in: source.zone, from: source.date).day
            == display.dateComponents(in: target, from: source.date).day
        let time = clockString(source.date, zone: target, calendar: calendar)
        let dayNote = sameDay ? "" : " (\(dayOffsetWord(source, target: target, calendar: calendar)))"

        return CalcResult(
            expression: clockString(source.date, zone: source.zone, calendar: calendar),
            sourceBadge: label(for: source.zone),
            targetBadge: label(for: target),
            payload: .value(display: time + dayNote, copyText: time))
    }

    private struct SourceMoment {
        let date: Date
        let zone: TimeZone
    }

    private static func sourceMoment(
        _ words: [String], now: Date, calendar: Calendar
    ) -> SourceMoment? {
        let words = words.filter { !["what", "whats", "the", "is", "it", "current"].contains($0) }
        guard let head = words.first else { return nil }
        guard head == "time" || head == "now" || head == "clock" || parseClock(head) != nil else {
            return nil
        }

        let rest = Array(words.dropFirst())
        let zone = rest.isEmpty ? calendar.timeZone : (self.zone(named: rest) ?? calendar.timeZone)
        if head == "time" || head == "now" || head == "clock" {
            guard rest.isEmpty || self.zone(named: rest) != nil else { return nil }
            return SourceMoment(date: now, zone: zone)
        }

        guard let clock = parseClock(head) else { return nil }
        var source = calendar
        source.timeZone = zone
        let day = source.dateComponents([.year, .month, .day], from: now)
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = clock.hour
        components.minute = clock.minute
        components.timeZone = zone
        guard let date = source.date(from: components) else { return nil }
        return SourceMoment(date: date, zone: zone)
    }

    private static func parseClock(_ word: String) -> (hour: Int, minute: Int)? {
        var text = word
        var meridiem: String?
        for suffix in ["am", "pm"] where text.hasSuffix(suffix) {
            meridiem = suffix
            text.removeLast(2)
        }
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard let hour = Int(parts[0]) else { return nil }
        let minute = parts.count > 1 ? Int(parts[1]) : 0
        guard let minute, (0...59).contains(minute) else { return nil }

        guard let meridiem else {
            // A bare number is a search ("time in 5"), so only a written clock qualifies.
            guard text.contains(":"), (0...23).contains(hour) else { return nil }
            return (hour, minute)
        }
        guard (1...12).contains(hour) else { return nil }
        return (meridiem == "pm" ? (hour % 12) + 12 : hour % 12, minute)
    }

    private static func zone(named words: [String]) -> TimeZone? {
        let phrase = words.joined(separator: " ")
        if let identifier = aliases[phrase] { return TimeZone(identifier: identifier) }
        guard let identifier = cities[phrase] else { return nil }
        return TimeZone(identifier: identifier)
    }

    /// Foundation already carries the IANA database, so nothing here is generated.
    private static let cities: [String: String] = {
        var table: [String: String] = [:]
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            guard let city = identifier.split(separator: "/").last else { continue }
            table[city.replacingOccurrences(of: "_", with: " ").lowercased()] = identifier
        }
        return table
    }()

    /// `TimeZone.abbreviationDictionary` is unusable here: its `BDT` is the Bangladeshi taka.
    /// IATA codes are Foundation-less by nature, so the airport half is a curated product choice.
    private static let aliases: [String: String] = [
        "utc": "UTC", "gmt": "GMT", "zulu": "UTC",
        "est": "America/New_York", "edt": "America/New_York", "et": "America/New_York",
        "cst": "America/Chicago", "cdt": "America/Chicago", "ct": "America/Chicago",
        "mst": "America/Denver", "mdt": "America/Denver", "mt": "America/Denver",
        "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pt": "America/Los_Angeles",
        "cet": "Europe/Paris", "cest": "Europe/Paris", "bst": "Europe/London",
        "ist": "Asia/Kolkata", "jst": "Asia/Tokyo", "kst": "Asia/Seoul",
        "aest": "Australia/Sydney", "aedt": "Australia/Sydney",
        "nyc": "America/New_York", "new york city": "America/New_York",
        "la": "America/Los_Angeles", "sf": "America/Los_Angeles",
        "san francisco": "America/Los_Angeles", "silicon valley": "America/Los_Angeles",
        "seattle": "America/Los_Angeles", "boston": "America/New_York",
        "washington": "America/New_York", "dc": "America/New_York",
        "austin": "America/Chicago", "dallas": "America/Chicago", "houston": "America/Chicago",
        "miami": "America/New_York", "atlanta": "America/New_York",
        "philadelphia": "America/New_York", "las vegas": "America/Los_Angeles",
        "ldn": "Europe/London", "sfo": "America/Los_Angeles", "lax": "America/Los_Angeles",
        "jfk": "America/New_York", "sgp": "Asia/Singapore",
        "kolkata": "Asia/Kolkata", "bengaluru": "Asia/Kolkata",
        "bangalore": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata",
        "new delhi": "Asia/Kolkata", "chennai": "Asia/Kolkata", "hyderabad": "Asia/Kolkata",
        "saigon": "Asia/Ho_Chi_Minh", "hcmc": "Asia/Ho_Chi_Minh",
        "munich": "Europe/Berlin", "frankfurt": "Europe/Berlin", "hamburg": "Europe/Berlin",
        "cologne": "Europe/Berlin", "milan": "Europe/Rome", "barcelona": "Europe/Madrid",
        "geneva": "Europe/Zurich", "st petersburg": "Europe/Moscow",
        "kyiv": "Europe/Kyiv", "tel aviv": "Asia/Tel_Aviv", "osaka": "Asia/Tokyo",
        "kyoto": "Asia/Tokyo", "shenzhen": "Asia/Shanghai", "beijing": "Asia/Shanghai",
        "guangzhou": "Asia/Shanghai", "melbourne": "Australia/Melbourne",
        "brisbane": "Australia/Brisbane", "perth": "Australia/Perth",
        "rio": "America/Sao_Paulo", "rio de janeiro": "America/Sao_Paulo",
        "cdmx": "America/Mexico_City", "mexico city": "America/Mexico_City",
        // IATA airport codes. `MAD` is omitted: it is the Moroccan dirham, and money wins.
        "vie": "Europe/Vienna", "lhr": "Europe/London", "lgw": "Europe/London",
        "cdg": "Europe/Paris", "ory": "Europe/Paris", "fra": "Europe/Berlin",
        "muc": "Europe/Berlin", "txl": "Europe/Berlin", "ber": "Europe/Berlin",
        "ams": "Europe/Amsterdam", "bcn": "Europe/Madrid", "zrh": "Europe/Zurich",
        "gva": "Europe/Zurich", "cph": "Europe/Copenhagen", "osl": "Europe/Oslo",
        "arn": "Europe/Stockholm", "hel": "Europe/Helsinki", "dub": "Europe/Dublin",
        "lis": "Europe/Lisbon", "ath": "Europe/Athens", "prg": "Europe/Prague",
        "waw": "Europe/Warsaw", "bud": "Europe/Budapest",
        "svo": "Europe/Moscow", "led": "Europe/Moscow", "fco": "Europe/Rome",
        "mxp": "Europe/Rome", "bru": "Europe/Brussels",
        "dxb": "Asia/Dubai", "auh": "Asia/Dubai", "doh": "Asia/Qatar",
        "bom": "Asia/Kolkata", "del": "Asia/Kolkata", "blr": "Asia/Kolkata",
        "hkg": "Asia/Hong_Kong", "pvg": "Asia/Shanghai", "pek": "Asia/Shanghai",
        "icn": "Asia/Seoul", "nrt": "Asia/Tokyo", "hnd": "Asia/Tokyo",
        "kix": "Asia/Tokyo", "sin": "Asia/Singapore", "bkk": "Asia/Bangkok",
        "kul": "Asia/Kuala_Lumpur", "cgk": "Asia/Jakarta", "mnl": "Asia/Manila",
        "tlv": "Asia/Tel_Aviv",
        "syd": "Australia/Sydney", "mel": "Australia/Melbourne",
        "bne": "Australia/Brisbane", "per": "Australia/Perth", "akl": "Pacific/Auckland",
        "yyz": "America/Toronto", "yvr": "America/Vancouver", "yul": "America/Toronto",
        "ord": "America/Chicago", "dfw": "America/Chicago", "iah": "America/Chicago",
        "atl": "America/New_York", "sea": "America/Los_Angeles", "den": "America/Denver",
        "bos": "America/New_York", "mia": "America/New_York", "phx": "America/Phoenix",
        "ewr": "America/New_York", "iad": "America/New_York",
        "gru": "America/Sao_Paulo", "eze": "America/Argentina/Buenos_Aires",
        "scl": "America/Santiago", "bog": "America/Bogota", "lim": "America/Lima",
        "mex": "America/Mexico_City",
        "jnb": "Africa/Johannesburg", "cpt": "Africa/Johannesburg", "cai": "Africa/Cairo",
        "nbo": "Africa/Nairobi", "los": "Africa/Lagos", "cmn": "Africa/Casablanca"
    ]

    /// Not `localizedName`, which needs a `Locale` — banned in `Model/`.
    private static func label(for zone: TimeZone) -> String {
        if zone.identifier == "GMT" || zone.identifier == "UTC" { return "UTC" }
        guard let city = zone.identifier.split(separator: "/").last else { return zone.identifier }
        return city.replacingOccurrences(of: "_", with: " ")
    }

    private static func clockString(_ date: Date, zone: TimeZone, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = calendar.locale ?? Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func dayOffsetWord(
        _ source: SourceMoment, target: TimeZone, calendar: Calendar
    ) -> String {
        var here = calendar
        here.timeZone = source.zone
        var there = calendar
        there.timeZone = target
        let from = here.startOfDay(for: source.date)
        let to = there.startOfDay(for: source.date)
        return to < from ? "yesterday" : "tomorrow"
    }
}
