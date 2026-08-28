import Foundation

/// Reuses `DateFormatter`s across calls: building one costs ~160 µs against ~0.5 µs to reuse it,
/// and a date card formats up to four times. Keyed by everything a formatter is configured with.
enum CalcDateFormatters {
    private struct Key: Hashable {
        let pattern: String
        let zone: String
        let locale: String
        let calendar: Calendar.Identifier
    }

    /// Cleared wholesale rather than evicted: the keys are a handful of patterns and one zone.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Key: DateFormatter] = [:]

    static func string(from date: Date, calendar: Calendar, zone: TimeZone, pattern: String) -> String {
        let locale = calendar.locale ?? Locale(identifier: "en_US")
        let key = Key(
            pattern: pattern, zone: zone.identifier, locale: locale.identifier,
            calendar: calendar.identifier)

        lock.lock()
        defer { lock.unlock() }
        if let formatter = cache[key] { return formatter.string(from: date) }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        // Follow the injected calendar's locale so weekday/month names match the user's language.
        formatter.locale = locale
        formatter.dateFormat = pattern
        // A zone table plus a few patterns, so the ceiling is bounded by what the grammars format.
        if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
        cache[key] = formatter
        return formatter.string(from: date)
    }
}
