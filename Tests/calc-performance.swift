import Foundation

@main
struct CalcPerformance {
    struct Group {
        let name: String
        let queries: [String]
    }

    static let groups = [
        Group(name: "search", queries: ["s", "safari", "visual studio code", "calendar", "slack", "terminal", "notes"]),
        Group(name: "arithmetic", queries: [
            "2+2", "19*27", "(123+456)/7", "sqrt(144)", "2^10", "sin(30deg)", "15% of 240", "round(3.14159)"
        ]),
        Group(name: "units", queries: [
            "10kg + 500g to lb", "100km/h to mph", "1 gal to L", "5 feet 3 inches", "55h in workdays",
            "1GB to MB", "20c to f", "1m"
        ]),
        Group(name: "currency", queries: ["20 eur to usd", "$10 + €5", "1 btc to eur", "25 eur"]),
        Group(name: "dates", queries: [
            "now + 90 min", "days till monday", "today + 3 weeks", "jul 4 - today", "3 days from today",
            "17.2.26 + 10 weekdays", "monday in 3 weeks"
        ]),
        Group(name: "zones", queries: ["time in Tokyo", "5pm ldn in sf", "diff tokyo"]),
        Group(name: "partial", queries: ["2+", "(123+456)/", "10kg +", "$10 +", "255 to hex +"]),
        Group(name: "advanced", queries: [
            "5m * 4m to ft2", "100km / 2h to km/h", "sqrt(25m2)", "12V / 6ohm", "hypot(3,4)",
            "1GB / 10MB/s to s", "100 USD / 4hr * 8hr", "1km == 1000m", "now to unix ms"
        ])
    ]

    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let now = Date(timeIntervalSince1970: 1_788_775_200)
        let rates = CurrencyRates(base: "EUR", rates: ["USD": 1.1, "GBP": 0.85, "BTC": 0.00002], fetchedAt: now)
        func evaluate(_ query: String) -> CalcResult? {
            CalcEngine.evaluate(query, now: now, calendar: calendar, rates: rates, region: "EUR")
        }
        func output(_ result: CalcResult?) -> [String] {
            guard let result else { return ["nil"] }
            let fields = [result.expression, result.sourceBadge ?? "", result.targetBadge ?? ""]
            switch result.payload {
            case .value(let display, let copy): return fields + [display, copy]
            case .error(let message): return fields + ["error", message]
            }
        }
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--probe" {
            let queries = arguments.count > 1 ? Array(arguments.dropFirst()) : groups.flatMap(\.queries)
            let rows = queries.map { ["query": [$0], "output": output(evaluate($0))] }
            print(String(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), encoding: .utf8)!)
            return
        }
        if arguments.first == "--cold" {
            let query = arguments.dropFirst().first ?? "2+2"
            let start = ContinuousClock.now
            let result = evaluate(query)
            let elapsed = microseconds(start.duration(to: .now))
            print(String(data: try JSONSerialization.data(withJSONObject: [
                "us": elapsed, "output": output(result)
            ], options: [.sortedKeys]), encoding: .utf8)!)
            return
        }
        let iterations = arguments.first.flatMap(Int.init) ?? 2000
        var rows: [[String: Any]] = []
        for group in groups {
            let outputs = group.queries.map { output(evaluate($0)) }
            var checksum = 0
            let start = ContinuousClock.now
            for _ in 0..<iterations {
                for query in group.queries {
                    if let answer = evaluate(query) {
                        switch answer.payload {
                        case .value(_, let copy): checksum &+= copy.utf8.count
                        case .error(let message): checksum &+= message.utf8.count
                        }
                    }
                }
            }
            rows.append([
                "group": group.name, "queries": group.queries, "outputs": outputs, "checksum": checksum,
                "us": microseconds(start.duration(to: .now)) / Double(iterations * group.queries.count)
            ])
        }
        print(String(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), encoding: .utf8)!)
    }

    static func microseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1e6 + Double(parts.attoseconds) / 1e12
    }
}
