import Foundation

enum CalcTimestamp {
    private static let isoPattern = try? NSRegularExpression(
        pattern: #"^(\d{4})-(\d{2})-(\d{2})[tT](\d{2}):(\d{2}):(\d{2})(\.\d{1,9})?([zZ]|[+-]\d{2}:\d{2})$"#)

    static func looksLikeISO(_ text: String) -> Bool {
        let bytes = text.utf8
        guard bytes.count >= 20 else { return false }
        let separator = bytes.dropFirst(10).first
        return separator == 84 || separator == 116
    }

    static func isoDate(_ text: String) -> Date? {
        guard looksLikeISO(text) else { return nil }
        let source = text as NSString
        guard let match = isoPattern?.firstMatch(in: text, range: NSRange(location: 0, length: source.length)),
            match.range.length == source.length else { return nil }
        let parts = (1...6).compactMap { Int(source.substring(with: match.range(at: $0))) }
        guard parts.count == 6, (1...9999).contains(parts[0]), (0...23).contains(parts[3]),
            (0...59).contains(parts[4]), (0...59).contains(parts[5]) else { return nil }
        let suffix = source.substring(with: match.range(at: 8))
        var offset = 0
        if suffix.count > 1 {
            let numbers = suffix.dropFirst().split(separator: ":").compactMap { Int($0) }
            guard numbers.count == 2, numbers[0] <= 23, numbers[1] <= 59 else { return nil }
            offset = (numbers[0] * 3600 + numbers[1] * 60) * (suffix.first == "-" ? -1 : 1)
        }
        guard let zone = TimeZone(secondsFromGMT: offset) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2],
            hour: parts[3], minute: parts[4], second: parts[5])
        guard let date = calendar.date(from: components),
            calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == components
        else { return nil }
        let fraction = match.range(at: 7)
        return date.addingTimeInterval(fraction.location == NSNotFound ? 0 : Double(source.substring(with: fraction)) ?? 0)
    }

    static func epochDate(_ text: String) -> Date? {
        guard text.contains("unix") || text.contains("timestamp") else { return nil }
        let words = text.split(separator: " ").map(String.init)
        guard (2...3).contains(words.count) else { return nil }
        let number: String
        if words[0] == "unix" || words[0] == "timestamp" {
            number = words[1]
        } else if words[1] == "unix" || words[1] == "timestamp" {
            number = words[0]
        } else { return nil }
        let milliseconds = words.count == 3 && ["ms", "milliseconds"].contains(words[2])
        guard words.count == 2 || milliseconds || ["s", "seconds"].contains(words[2]),
            let value = Double(number), value.isFinite else { return nil }
        let seconds = value / (milliseconds ? 1000 : 1)
        guard (-62_135_596_800..<253_402_300_800).contains(seconds) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func scale(_ target: String) -> Double? {
        switch target {
        case "unix", "timestamp", "unix timestamp", "unix s", "unix seconds": return 1
        case "unix ms", "unix milliseconds", "timestamp ms", "timestamp milliseconds": return 1000
        default: return nil
        }
    }
}
