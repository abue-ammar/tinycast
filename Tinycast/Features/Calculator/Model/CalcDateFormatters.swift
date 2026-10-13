import Foundation

/// Reused across calls: building one costs ~160 µs against ~0.5 µs to reuse it.
enum CalcDateFormatters {
    private enum Layout: Hashable {
        case pattern(String)
        case template(String)
    }

    private struct Key: Hashable {
        let layout: Layout
        let zone: String
        let locale: String
        /// Not in `locale.identifier`, so a 24-hour switch would otherwise hit a stale formatter.
        let hourCycle: Locale.HourCycle
        let calendar: Calendar.Identifier
    }

    /// Cleared wholesale rather than evicted: the keys are a handful of patterns and one zone.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Key: DateFormatter] = [:]

    static func string(from date: Date, calendar: Calendar, zone: TimeZone, pattern: String) -> String {
        string(from: date, calendar: calendar, zone: zone, layout: .pattern(pattern))
    }

    /// For clock times: a `j` lets the locale and the 24-hour switch choose between `h a` and `HH`.
    static func string(from date: Date, calendar: Calendar, zone: TimeZone, template: String) -> String {
        string(from: date, calendar: calendar, zone: zone, layout: .template(template))
    }

    private static func string(
        from date: Date, calendar: Calendar, zone: TimeZone, layout: Layout
    ) -> String {
        let locale = calendar.locale ?? Locale(identifier: "en_US")
        let key = Key(
            layout: layout, zone: zone.identifier, locale: locale.identifier,
            hourCycle: locale.hourCycle, calendar: calendar.identifier)

        lock.lock()
        defer { lock.unlock() }
        if let formatter = cache[key] { return formatter.string(from: date) }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        // Follow the injected calendar's locale so weekday/month names match the user's language.
        formatter.locale = locale
        switch layout {
        case .pattern(let pattern): formatter.dateFormat = pattern
        case .template(let template):
            formatter.setLocalizedDateFormatFromTemplate(template)
            // ICU puts U+202F before AM/PM; a plain space keeps a pasted answer plain text.
            formatter.dateFormat = formatter.dateFormat.replacing("\u{202F}", with: " ")
        }
        // A zone table plus a few patterns, so the ceiling is bounded by what the grammars format.
        if cache.count >= 64 { cache.removeAll(keepingCapacity: true) }
        cache[key] = formatter
        return formatter.string(from: date)
    }
}
