import Foundation

enum CalcTimeZone {
    static func evaluate(_ raw: String, now: Date, calendar: Calendar) -> CalcResult? {
        guard raw.count <= 128, raw.contains(where: \.isWhitespace) else { return nil }
        let inputWords = raw.split(whereSeparator: \.isWhitespace)
        let typedWords = inputWords.map { $0.lowercased() }
        let lowerWords = withoutFillers(typedWords)
        if lowerWords != typedWords {
            return evaluate(lowerWords.joined(separator: " "), now: now, calendar: calendar)
        }
        if let query = whenQuery(lowerWords) ?? currentTimeQuery(lowerWords) {
            return evaluate(query, now: now, calendar: calendar)
        }
        if let date = currentDate(lowerWords, now: now, calendar: calendar) { return date }
        if raw.utf8.contains(44), let list = worldClock(raw.lowercased(), now: now, calendar: calendar) {
            return list
        }
        if Self.hintsAtClock(raw) {
            let lowered = raw.lowercased()
            if let range = clockRange(lowered, now: now, calendar: calendar) { return range }
            if let dated = datedMoment(lowered, now: now, calendar: calendar) { return dated }
        }
        guard inputWords.count >= 2,
            inputWords.contains(where: { connectors.contains($0.lowercased()) })
                || parseClock(inputWords[0].lowercased()) != nil
                || parseClock(inputWords.prefix(2).joined().lowercased()) != nil
        else {
            return nil
        }
        // The last word decides: `10 km to mi` carries a connector too.
        guard endsInZoneOrDuration(inputWords[inputWords.count - 1].lowercased()) else { return nil }

        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return nil }

        if let difference = offsetBetween(query, now: now, calendar: calendar) { return difference }

        // A trailing `± <n> <unit>` shifts the answer, so `5pm ldn in sf + 2h` is still one query.
        let (zoneQuery, offset) = splitOffset(query)
        let words = zoneQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 2 else { return nil }

        let target: TimeZone
        let leading: [String]
        var ahead: (count: Int, component: Calendar.Component)?
        if let connector = words.lastIndex(where: { $0 == "in" || $0 == "to" || $0 == "at" }) {
            let targetWords = Array(words[(connector + 1)...])
            guard !targetWords.isEmpty else { return nil }
            // `time in 4 hours` names a duration where a zone would go, so the home zone answers.
            if let zone = zone(named: targetWords) {
                target = zone
            } else if let duration = parseDuration(targetWords.joined(separator: " ")) {
                target = calendar.timeZone
                ahead = duration
            } else {
                return nil
            }
            leading = Array(words[0..<connector])
        } else {
            var sourceWords = words
            if sourceWords[1] == "am" || sourceWords[1] == "pm" {
                let meridiem = sourceWords.remove(at: 1)
                sourceWords[0] += meridiem
            }
            guard parseClock(sourceWords[0]) != nil,
                zone(named: Array(sourceWords.dropFirst())) != nil
            else { return nil }
            leading = sourceWords
            target = calendar.timeZone
        }

        guard
            var source = sourceMoment(
                leading, allowZoneConnector: ahead == nil, now: now, calendar: calendar)
        else { return nil }
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

        guard let dayNote = dayOffsetNote(source, target: target, calendar: calendar) else { return nil }
        let time = clockString(source.date, zone: target, calendar: calendar)

        return CalcResult(
            expression: clockString(source.date, zone: source.zone, calendar: calendar),
            sourceBadge: label(for: source.zone),
            targetBadge: label(for: target),
            payload: .value(display: time + dayNote, copyText: time))
    }

    private static func currentTimeQuery(_ words: [String]) -> String? {
        if words.first == "time" || words.first == "timezone" {
            var place = Array(words.dropFirst())
            if words.first == "timezone", place.first == "in" { place.removeFirst() }
            if zone(named: place) != nil { return "time in \(place.joined(separator: " "))" }
        }

        let destination = words.firstIndex(of: "to") ?? words.endIndex
        var place = Array(words[..<destination])
        if place.suffix(2) == ["time", "zone"] {
            place.removeLast(2)
        } else if place.last == "time" || place.last == "timezone" {
            place.removeLast()
        } else {
            return nil
        }
        guard zone(named: place) != nil else { return nil }
        guard destination < words.endIndex else { return "time in \(place.joined(separator: " "))" }
        let target = Array(words[(destination + 1)...])
        guard zone(named: target) != nil else { return nil }
        return "time \(place.joined(separator: " ")) to \(target.joined(separator: " "))"
    }

    /// A written clock has a colon or an am/pm after a digit; anything else skips the dated forms.
    private static func hintsAtClock(_ text: String) -> Bool {
        var previous: UInt8 = 0
        var beforePrevious: UInt8 = 0
        for byte in text.utf8 {
            if byte == 58 { return true }
            if byte | 0x20 == 109, previous | 0x20 == 97 || previous | 0x20 == 112,
                (48...57).contains(beforePrevious) || beforePrevious == 32
            {
                return true
            }
            (beforePrevious, previous) = (previous, byte)
        }
        return false
    }

    /// Splits a trailing `+ 2h` / `- 30 min` off the zone phrase it shifts.
    static func splitOffset(
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

    struct SourceMoment {
        let date: Date
        let zone: TimeZone
    }

    private static func endsInZoneOrDuration(_ tail: String) -> Bool {
        // Folded, because the identifiers carry no accents while `zürich` and `são paulo` do.
        let folded = tail.folding(options: [.diacriticInsensitive], locale: nil)
        if zoneIdentifier(named: folded) != nil { return true }
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

    /// The final word of every multi-word name in any table, so `in new york` still reaches it.
    private static let citySuffixes: Set<String> = {
        var tails: Set<String> = []
        for names in [cities.keys, aliases.keys, CountryZoneData.zones.keys] {
            for name in names where name.contains(" ") {
                if let last = name.split(separator: " ").last { tails.insert(String(last)) }
            }
        }
        return tails
    }()

    private static let connectors: Set<String> = ["in", "to", "at", "diff", "difference"]

    /// `diff paris` runs from the Mac's own zone; `diff london and tokyo` from the first place named.
    private static func offsetBetween(
        _ query: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        var words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.first == "time" { words.removeFirst() }
        guard words.count >= 2, words[0] == "diff" || words[0] == "difference" else { return nil }
        words.removeFirst()
        if words.first == "between" { words.removeFirst() }
        guard let (home, target) = zonePair(words) ?? zone(named: words).map({ (calendar.timeZone, $0) })
        else {
            return nil
        }

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

    /// Two places, split at `and` / `&` or, failing that, wherever both halves name a zone.
    private static func zonePair(_ words: [String]) -> (TimeZone, TimeZone)? {
        if let joiner = words.firstIndex(where: { $0 == "and" || $0 == "&" }) {
            guard let first = zone(named: Array(words[..<joiner])),
                let second = zone(named: Array(words[(joiner + 1)...]))
            else { return nil }
            return (first, second)
        }
        guard words.count >= 2 else { return nil }
        for split in 1..<words.count {
            if let first = zone(named: Array(words[..<split])),
                let second = zone(named: Array(words[split...]))
            {
                return (first, second)
            }
        }
        return nil
    }

    // MARK: - Worded questions

    private static func withoutFillers(_ words: [String]) -> [String] {
        guard words.count > 2 else { return words }
        var words = words
        if words[0] == "local", words[1] == "time" {
            words.removeFirst()
        } else if words.suffix(2) == ["local", "time"] {
            words.remove(at: words.count - 2)
        }
        guard words.first == "time", words.count > 2 else { return words }
        if words[1] == "now" {
            words.remove(at: 1)
        } else if words.last == "now" {
            words.removeLast()
        }
        return words
    }

    /// `time in tokyo when it's 5pm in london` asks what `5pm london in tokyo` answers.
    private static func whenQuery(_ words: [String]) -> String? {
        guard let when = words.firstIndex(of: "when") else { return nil }
        let fillers: Set<String> = ["what", "whats", "is", "it", "its", "it's", "it’s"]
        var asked = words[..<when].filter { !fillers.contains($0) }
        guard asked.first == "time" else { return nil }
        asked.removeFirst()
        if asked.first == "in" || asked.first == "at" { asked.removeFirst() }
        let given = words[(when + 1)...].filter { !fillers.contains($0) && $0 != "in" && $0 != "at" }
        guard !asked.isEmpty, given.count >= 2, zone(named: Array(asked)) != nil else { return nil }
        return given.joined(separator: " ") + " in " + asked.joined(separator: " ")
    }

    private static func currentDate(_ words: [String], now: Date, calendar: Calendar) -> CalcResult? {
        var place = words
        if place.first == "date" {
            place.removeFirst()
            if place.first == "in" || place.first == "at" { place.removeFirst() }
        } else if place.last == "date" {
            place.removeLast()
        } else {
            return nil
        }
        guard !place.isEmpty, let zone = zone(named: place) else { return nil }
        let text = CalcDateFormatters.string(
            from: now, calendar: calendar, zone: zone, pattern: "EEEE, d MMMM")
        return CalcResult(
            expression: words.joined(separator: " "), sourceBadge: String(localized: "Date"),
            targetBadge: label(for: zone), payload: .value(display: text, copyText: text))
    }

    private static func sourceMoment(
        _ words: [String], allowZoneConnector: Bool, now: Date, calendar: Calendar
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

        guard var head = words.first else { return nil }
        var rest = Array(words.dropFirst())
        if rest.first == "am" || rest.first == "pm" {
            guard !head.hasSuffix("am"), !head.hasSuffix("pm") else { return nil }
            head += rest.removeFirst()
        }
        guard head == "time" || head == "now" || head == "clock" || parseClock(head) != nil else {
            return nil
        }

        if allowZoneConnector, rest.first == "in" || rest.first == "at" {
            rest.removeFirst()
            guard !rest.isEmpty else { return nil }
        }
        guard let zone = rest.isEmpty ? calendar.timeZone : self.zone(named: rest) else { return nil }
        if head == "time" || head == "now" || head == "clock" {
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
        let resolved = source.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard resolved.year == components.year, resolved.month == components.month,
            resolved.day == components.day, resolved.hour == components.hour,
            resolved.minute == components.minute
        else { return nil }
        guard let ahead else { return SourceMoment(date: date, zone: zone) }
        guard let shifted = source.date(byAdding: ahead.component, value: ahead.count, to: date)
        else { return nil }
        return SourceMoment(date: shifted, zone: zone)
    }

    static func parseClock(_ word: String) -> (hour: Int, minute: Int)? {
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

    static func zone(named words: [String]) -> TimeZone? {
        // `são paulo` and `zürich` are how the cities are spelled; the identifiers are not.
        let phrase = words.joined(separator: " ")
            .folding(options: [.diacriticInsensitive], locale: nil)
        return zoneIdentifier(named: phrase).flatMap(TimeZone.init(identifier:))
    }

    /// A curated alias outranks a city, and a city outranks a country sharing its spelling.
    private static func zoneIdentifier(named phrase: String) -> String? {
        aliases[phrase] ?? cities[phrase] ?? CountryZoneData.zones[phrase] ?? offsetIdentifier(phrase)
    }

    /// `utc+5`, `gmt-5`, `utc+5:30` — attached, since a spaced `+` is a shift.
    private static func offsetIdentifier(_ phrase: String) -> String? {
        guard phrase.hasPrefix("utc") || phrase.hasPrefix("gmt"), phrase.count > 4 else { return nil }
        let body = phrase.dropFirst(3)
        guard let sign = body.first, sign == "+" || sign == "-" else { return nil }
        let parts = body.dropFirst().split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), (1...2).contains(parts[0].count),
            let hours = Int(parts[0]), hours <= 14
        else { return nil }
        var minutes = 0
        if parts.count == 2 {
            guard parts[1].count == 2, let parsed = Int(parts[1]), parsed < 60 else { return nil }
            minutes = parsed
        }
        return "GMT" + String(sign) + String(format: "%02d%02d", hours, minutes)
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
            "est", "edt", "et", "usa", "nyc", "new york city", "boston", "washington", "dc", "miami",
            "atlanta",
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
        "Asia/Dubai": ["uae", "dxb", "auh", "sharjah"],
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

    private static let aliases: [String: String] = {
        var table: [String: String] = [:]
        table.reserveCapacity(aliasGroups.values.reduce(0) { $0 + $1.count })
        for (zone, names) in aliasGroups {
            for name in names { table[name] = zone }
        }
        return table
    }()

    /// Not `localizedName`, which needs a `Locale` — banned in `Model/`.
    static func label(for zone: TimeZone) -> String {
        if zone.identifier == "GMT" || zone.identifier == "UTC" { return "UTC" }
        if zone.identifier.hasPrefix("GMT+") || zone.identifier.hasPrefix("GMT-") {
            let seconds = zone.secondsFromGMT()
            let minutes = abs(seconds) / 60
            let tail =
                minutes % 60 == 0 ? "\(minutes / 60)" : String(format: "%d:%02d", minutes / 60, minutes % 60)
            return "UTC" + (seconds < 0 ? "-" : "+") + tail
        }
        guard let city = zone.identifier.split(separator: "/").last else { return zone.identifier }
        return city.replacingOccurrences(of: "_", with: " ")
    }

    static func clockString(_ date: Date, zone: TimeZone, calendar: Calendar) -> String {
        CalcDateFormatters.string(from: date, calendar: calendar, zone: zone, template: "jmm")
    }

    static func dayOffsetNote(
        _ source: SourceMoment, target: TimeZone, calendar: Calendar
    ) -> String? {
        var here = calendar
        here.timeZone = source.zone
        var there = calendar
        there.timeZone = target
        // Compare civil dates in one zone so offsets and DST cannot shorten the day count.
        var dates = calendar
        dates.timeZone = .gmt
        guard
            let from = dates.date(from: here.dateComponents([.era, .year, .month, .day], from: source.date)),
            let to = dates.date(from: there.dateComponents([.era, .year, .month, .day], from: source.date)),
            let days = dates.dateComponents([.day], from: from, to: to).day
        else { return nil }
        guard days != 0 else { return "" }
        var relative = Date.AnchoredRelativeFormatStyle(
            anchor: to, presentation: .named, locale: calendar.locale ?? Locale(identifier: "en_US"),
            calendar: dates)
        relative.allowedFields = [.day]
        return " (\(from.formatted(relative)))"
    }
}
