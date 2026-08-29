import Foundation

/// Clock time in another city. See docs/features/calculator.md.
enum CalcTimeZone {
    static func evaluate(_ raw: String, now: Date, calendar: Calendar) -> CalcResult? {
        // Every grammar carries a connector, so an app search stops before allocating.
        guard raw.count <= 128, raw.contains(where: \.isWhitespace), hasConnector(raw) else {
            return nil
        }
        // The last word decides: `10 km to mi` carries a connector too.
        guard endsInZoneOrDuration(raw) else { return nil }

        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return nil }

        if let difference = offsetBetween(query, now: now, calendar: calendar) { return difference }

        // A trailing `± <n> <unit>` shifts the answer, so `5pm ldn in sf + 2h` is still one query.
        let (zoneQuery, offset) = splitOffset(query)
        let words = zoneQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return nil }

        // Every grammar needs a connector, so an app search never touches the zone table.
        guard let connector = words.lastIndex(where: { $0 == "in" || $0 == "to" || $0 == "at" })
        else { return nil }
        let targetWords = Array(words[(connector + 1)...])
        guard !targetWords.isEmpty else { return nil }

        // `time in 4 hours` names a duration where a zone would go, so the home zone answers.
        let target: TimeZone
        var ahead: (count: Int, component: Calendar.Component)?
        if let zone = zone(named: targetWords) {
            target = zone
        } else if let duration = parseDuration(targetWords.joined(separator: " ")) {
            target = calendar.timeZone
            ahead = duration
        } else {
            return nil
        }

        let leading = Array(words[0..<connector])
        guard var source = sourceMoment(leading, now: now, calendar: calendar) else { return nil }
        if let ahead {
            guard let shifted = calendar.date(byAdding: ahead.component, value: ahead.count, to: source.date)
            else { return nil }
            source = SourceMoment(date: shifted, zone: source.zone)
        }
        if let offset {
            guard
                let shifted = calendar.date(byAdding: offset.component, value: offset.count, to: source.date)
            else { return nil }
            source = SourceMoment(date: shifted, zone: source.zone)
        }

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

    /// Splits a trailing `+ 2h` / `- 30 min` off the zone phrase it shifts.
    private static func splitOffset(
        _ query: String
    ) -> (String, (count: Int, component: Calendar.Component)?) {
        for separator in [" + ", " - "] {
            guard let range = query.range(of: separator, options: .backwards) else { continue }
            let tail = String(query[range.upperBound...])
            guard let duration = parseDuration(tail, impliesHours: true) else { continue }
            let sign = separator == " - " ? -1 : 1
            return (String(query[..<range.lowerBound]), (duration.count * sign, duration.component))
        }
        return (query, nil)
    }

    /// `2h`, `90 min`, `2 hours` — sub-day only, since a zone answer is a clock time.
    private static func parseDuration(
        _ text: String, impliesHours: Bool = false
    ) -> (count: Int, component: Calendar.Component)? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let digits = compact.prefix { $0.isNumber }
        guard let count = Int(digits), count < 100_000 else { return nil }
        switch String(compact.dropFirst(digits.count)) {
        case "h", "hr", "hrs", "hour", "hours": return (count, .hour)
        case "m", "min", "mins", "minute", "minutes": return (count, .minute)
        case "s", "sec", "secs", "second", "seconds": return (count, .second)
        // A clock answer makes hours the only sensible unit for a bare `+ 5`.
        case "" where impliesHours: return (count, .hour)
        default: return nil
        }
    }

    private struct SourceMoment {
        let date: Date
        let zone: TimeZone
    }

    /// Checked before the query is split, which keeps `10 km to mi` out of the zone path.
    private static func endsInZoneOrDuration(_ raw: String) -> Bool {
        var tail = ""
        for character in raw.reversed() {
            if character.isWhitespace {
                if !tail.isEmpty { break }
                continue
            }
            tail.insert(Character(character.lowercased()), at: tail.startIndex)
        }
        guard !tail.isEmpty else { return false }
        // Folded, because the identifiers carry no accents while `zürich` and `são paulo` do.
        let folded = tail.folding(options: [.diacriticInsensitive], locale: nil)
        if cities[folded] != nil || aliases[folded] != nil { return true }
        // `time in 4 hours` ends in the unit alone, so a bare unit word counts as a duration tail.
        if durationUnits.contains(folded) || parseDuration(folded, impliesHours: true) != nil {
            return true
        }
        // A multi-word city ("new york") only shows its last word here, so allow a known suffix.
        return citySuffixes.contains(folded)
    }

    private static let durationUnits: Set<String> = [
        "h", "hr", "hrs", "hour", "hours", "m", "min", "mins", "minute", "minutes",
        "s", "sec", "secs", "second", "seconds"
    ]

    /// The final word of every multi-word name in either table, so `in new york` still reaches it.
    private static let citySuffixes: Set<String> = {
        var tails: Set<String> = []
        for name in cities.keys where name.contains(" ") {
            if let last = name.split(separator: " ").last { tails.insert(String(last)) }
        }
        for name in aliases.keys where name.contains(" ") {
            if let last = name.split(separator: " ").last { tails.insert(String(last)) }
        }
        return tails
    }()

    /// Scans for a whole-word connector without lowercasing or splitting the whole query first.
    private static func hasConnector(_ raw: String) -> Bool {
        var word = ""
        for character in raw {
            if character.isWhitespace {
                if Self.connectors.contains(word.lowercased()) { return true }
                word = ""
            } else {
                word.append(character)
            }
        }
        return Self.connectors.contains(word.lowercased())
    }

    private static let connectors: Set<String> = ["in", "to", "at", "diff", "difference"]

    /// `diff paris`, `time diff paris` — how far a zone runs from the Mac's own.
    private static func offsetBetween(
        _ query: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        var words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.first == "time" { words.removeFirst() }
        guard words.count >= 2, words[0] == "diff" || words[0] == "difference",
            let target = zone(named: Array(words.dropFirst()))
        else { return nil }

        let home = calendar.timeZone
        let minutes =
            (target.secondsFromGMT(for: now) - home.secondsFromGMT(for: now)) / 60
        let sign = minutes < 0 ? "-" : "+"
        let whole = abs(minutes) / 60
        let part = abs(minutes) % 60
        let text = part == 0 ? "\(sign)\(whole)h" : "\(sign)\(whole)h \(part)m"

        return CalcResult(
            expression: clockString(now, zone: home, calendar: calendar),
            sourceBadge: label(for: home),
            targetBadge: label(for: target),
            payload: .value(
                display: "\(clockString(now, zone: target, calendar: calendar)) (\(text))",
                copyText: text))
    }

    private static func sourceMoment(
        _ words: [String], now: Date, calendar: Calendar
    ) -> SourceMoment? {
        var words = words.filter { !["what", "whats", "the", "is", "it", "current"].contains($0) }

        // `time in 4 hours in sf`: the leading half carries its own `in <duration>`.
        var ahead: (count: Int, component: Calendar.Component)?
        if let connector = words.lastIndex(where: { $0 == "in" || $0 == "at" }),
            connector + 1 < words.count,
            let duration = parseDuration(words[(connector + 1)...].joined(separator: " "))
        {
            ahead = duration
            words = Array(words[0..<connector])
        }

        guard let head = words.first else { return nil }
        guard head == "time" || head == "now" || head == "clock" || parseClock(head) != nil else {
            return nil
        }

        let rest = Array(words.dropFirst())
        let zone = rest.isEmpty ? calendar.timeZone : (self.zone(named: rest) ?? calendar.timeZone)
        if head == "time" || head == "now" || head == "clock" {
            guard rest.isEmpty || self.zone(named: rest) != nil else { return nil }
            guard let ahead else { return SourceMoment(date: now, zone: zone) }
            guard let shifted = calendar.date(byAdding: ahead.component, value: ahead.count, to: now)
            else { return nil }
            return SourceMoment(date: shifted, zone: zone)
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
        guard let ahead else { return SourceMoment(date: date, zone: zone) }
        guard let shifted = source.date(byAdding: ahead.component, value: ahead.count, to: date)
        else { return nil }
        return SourceMoment(date: shifted, zone: zone)
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
        // A lone ":" splits to nothing, so the first part is not guaranteed to exist.
        guard let first = parts.first, let hour = Int(first) else { return nil }
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
        // `são paulo` and `zürich` are how the cities are spelled; the identifiers are not.
        let phrase = words.joined(separator: " ")
            .folding(options: [.diacriticInsensitive], locale: nil)
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

    /// Curated: `abbreviationDictionary` is unusable, its `BDT` being the Bangladeshi taka.
    private static let aliasGroups: [String: [String]] = [
        "UTC": ["utc", "zulu"],
        "GMT": ["gmt"],
        "America/New_York": [
            "est", "edt", "et", "nyc", "new york city", "boston", "washington", "dc", "miami", "atlanta",
            "philadelphia", "jfk", "atl", "bos", "mia", "ewr", "iad", "charlotte", "nashville", "orlando",
            "tampa", "pittsburgh", "cleveland", "cincinnati", "columbus", "baltimore", "raleigh",
            "indianapolis", "louisville"
        ],
        "America/Chicago": [
            "cst", "cdt", "ct", "austin", "dallas", "houston", "ord", "dfw", "iah", "minneapolis", "st louis",
            "kansas city", "milwaukee", "new orleans", "memphis", "oklahoma city", "san antonio"
        ],
        "America/Denver": ["mst", "mdt", "mt", "den", "salt lake city", "albuquerque", "boise"],
        "America/Los_Angeles": [
            "pst", "pdt", "pt", "la", "sf", "san francisco", "silicon valley", "seattle", "las vegas", "sfo",
            "lax", "sea", "san diego", "san jose", "portland", "sacramento", "fresno", "oakland"
        ],
        "Europe/Paris": [
            "cet", "cest", "cdg", "ory", "lyon", "marseille", "toulouse", "nice", "bordeaux", "nantes",
            "lille", "strasbourg"
        ],
        "Europe/London": [
            "bst", "ldn", "lhr", "lgw", "manchester", "birmingham", "liverpool", "leeds", "glasgow",
            "edinburgh", "bristol", "cardiff", "cambridge", "oxford", "belfast"
        ],
        "Asia/Kolkata": [
            "ist", "kolkata", "bengaluru", "bangalore", "mumbai", "delhi", "new delhi", "chennai",
            "hyderabad", "bom", "del", "blr", "pune", "ahmedabad", "jaipur", "surat", "lucknow", "kanpur",
            "nagpur", "goa", "kochi", "indore", "thane", "bhopal", "visakhapatnam", "vizag", "patna",
            "vadodara", "ghaziabad", "ludhiana", "agra", "nashik", "faridabad", "meerut", "rajkot",
            "varanasi", "srinagar", "aurangabad", "amritsar", "navi mumbai", "allahabad", "prayagraj",
            "ranchi", "howrah", "coimbatore", "jabalpur", "gwalior", "vijayawada", "jodhpur", "madurai",
            "raipur", "chandigarh", "guwahati", "mysore", "mysuru", "gurgaon", "gurugram", "noida", "cochin",
            "trivandrum", "thiruvananthapuram", "panaji", "dehradun", "udaipur", "pondicherry", "puducherry",
            "jamshedpur", "bhubaneswar", "cuttack", "siliguri", "dhanbad", "kota", "shimla", "tirupati"
        ],
        "Asia/Tokyo": [
            "jst", "osaka", "kyoto", "nrt", "hnd", "kix", "yokohama", "nagoya", "sapporo", "fukuoka", "kobe",
            "hiroshima", "sendai", "okinawa", "nara"
        ],
        "Asia/Seoul": ["kst", "icn", "busan", "incheon", "daegu"],
        "Australia/Sydney": ["aest", "aedt", "syd", "canberra", "newcastle"],
        "Asia/Singapore": ["sgp", "sin"],
        "Asia/Ho_Chi_Minh": ["saigon", "hcmc", "hanoi", "haiphong", "hue", "da nang"],
        "Europe/Berlin": [
            "munich", "frankfurt", "hamburg", "cologne", "fra", "muc", "txl", "ber", "hannover", "hanover",
            "stuttgart", "dusseldorf", "dortmund", "essen", "leipzig", "dresden", "bremen", "nuremberg",
            "nurnberg", "bonn", "mannheim", "karlsruhe", "freiburg", "munster", "augsburg", "kiel", "koln",
            "munchen"
        ],
        "Europe/Rome": [
            "milan", "fco", "mxp", "naples", "turin", "florence", "venice", "bologna", "genoa", "palermo",
            "verona"
        ],
        "Europe/Madrid": ["barcelona", "bcn", "valencia", "seville", "malaga", "bilbao", "zaragoza"],
        "Europe/Zurich": [
            "geneva", "zrh", "gva", "basel", "bern", "lausanne", "lucerne", "luzern", "winterthur",
            "st gallen", "lugano"
        ],
        "Europe/Moscow": ["st petersburg", "svo", "led"],
        "Europe/Kyiv": ["kyiv", "lviv", "odesa"],
        "Asia/Tel_Aviv": ["tel aviv", "tlv"],
        "Asia/Shanghai": [
            "shenzhen", "beijing", "guangzhou", "pvg", "pek", "chengdu", "tianjin", "wuhan", "xian",
            "hangzhou", "nanjing", "qingdao", "suzhou", "shenyang", "kunming", "xiamen"
        ],
        "Australia/Melbourne": ["melbourne", "mel"],
        "Australia/Brisbane": ["brisbane", "bne", "gold coast"],
        "Australia/Perth": ["perth", "per"],
        "America/Sao_Paulo": [
            "rio", "rio de janeiro", "gru", "brasilia", "salvador", "curitiba", "porto alegre",
            "belo horizonte", "recife"
        ],
        "America/Mexico_City": ["cdmx", "mexico city", "mex", "guadalajara", "puebla"],
        "Europe/Vienna": [
            "vie", "graz", "salzburg", "linz", "innsbruck", "klagenfurt", "villach", "wels", "st polten",
            "dornbirn", "bregenz", "wien"
        ],
        "Europe/Amsterdam": ["ams", "rotterdam", "the hague", "den haag", "eindhoven", "utrecht"],
        "Europe/Copenhagen": ["cph", "aarhus", "odense"],
        "Europe/Oslo": ["osl", "bergen", "trondheim"],
        "Europe/Stockholm": ["arn", "gothenburg", "malmo"],
        "Europe/Helsinki": ["hel", "tampere", "turku"],
        "Europe/Dublin": ["dub", "cork", "galway"],
        "Europe/Lisbon": ["lis", "porto"],
        "Europe/Athens": ["ath", "thessaloniki"],
        "Europe/Prague": ["prg", "brno", "ostrava"],
        "Europe/Warsaw": ["waw", "krakow", "gdansk", "wroclaw", "poznan", "lodz"],
        "Europe/Budapest": ["bud"],
        "Europe/Brussels": ["bru", "antwerp", "ghent", "bruges"],
        "Asia/Dubai": ["dxb", "auh", "sharjah"],
        "Asia/Qatar": ["doh", "doha"],
        "Asia/Hong_Kong": ["hkg"],
        "Asia/Bangkok": ["bkk", "phuket", "chiang mai"],
        "Asia/Kuala_Lumpur": ["kul", "penang", "johor bahru"],
        "Asia/Jakarta": ["cgk", "surabaya", "medan", "bandung", "denpasar", "bali"],
        "Asia/Manila": ["mnl", "cebu", "davao"],
        "Pacific/Auckland": ["akl", "wellington", "christchurch"],
        "America/Toronto": ["yyz", "yul", "ottawa", "quebec", "montreal"],
        "America/Vancouver": ["yvr", "victoria"],
        "America/Phoenix": ["phx"],
        "America/Argentina/Buenos_Aires": ["eze", "rosario", "mendoza"],
        "America/Santiago": ["scl", "valparaiso"],
        "America/Bogota": ["bog", "medellin", "cali", "cartagena"],
        "America/Lima": ["lim", "arequipa"],
        "Africa/Johannesburg": ["jnb", "cpt", "durban", "pretoria", "soweto"],
        "Africa/Cairo": ["cai", "alexandria", "giza"],
        "Africa/Nairobi": ["nbo", "mombasa"],
        "Africa/Lagos": ["los", "abuja", "kano", "ibadan"],
        "Africa/Casablanca": ["cmn", "marrakech", "rabat", "fes", "tangier"],
        "Europe/Istanbul": ["ankara", "izmir"],
        "Asia/Karachi": ["lahore", "islamabad", "faisalabad", "rawalpindi", "multan", "peshawar"],
        "America/Guayaquil": ["quito"],
        "Europe/Malta": ["valletta"],
        "Asia/Dhaka": ["chittagong", "chattogram"],
        "Asia/Riyadh": ["jeddah", "mecca", "medina", "dammam"],
        "Asia/Taipei": ["kaohsiung", "taichung"],
        "Asia/Kuwait": ["kuwait city"],
        "Asia/Bahrain": ["manama"],
        "Asia/Jerusalem": ["haifa"],
        "America/Edmonton": ["calgary"]
    ]

    /// Flattened once from the grouping above, which is the form that gets edited.
    private static let aliases: [String: String] = {
        var table: [String: String] = [:]
        table.reserveCapacity(aliasGroups.values.reduce(0) { $0 + $1.count })
        for (zone, names) in aliasGroups {
            for name in names { table[name] = zone }
        }
        return table
    }()

    /// Not `localizedName`, which needs a `Locale` — banned in `Model/`.
    private static func label(for zone: TimeZone) -> String {
        if zone.identifier == "GMT" || zone.identifier == "UTC" { return "UTC" }
        guard let city = zone.identifier.split(separator: "/").last else { return zone.identifier }
        return city.replacingOccurrences(of: "_", with: " ")
    }

    private static func clockString(_ date: Date, zone: TimeZone, calendar: Calendar) -> String {
        CalcDateFormatters.string(from: date, calendar: calendar, zone: zone, pattern: "h:mm a")
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
