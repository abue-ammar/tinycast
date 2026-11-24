import Foundation

enum PlanUsageFormat {
    /// "3d 1h", "2h 14m"; never "0m", since a reset under a minute away is still ahead.
    static func duration(_ interval: TimeInterval, locale: Locale) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: [.days, .hours, .minutes], width: .narrow, maximumUnitCount: 2,
            fractionalPart: .hide(rounded: .down)
        )
        .locale(locale)
        return Duration.seconds(max(Int(interval), 60)).formatted(style)
    }

    static func resetTime(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let style = Date.FormatStyle(
            date: .omitted, time: .omitted, locale: locale, calendar: calendar,
            timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(style.hour().minute())
        }
        if date.timeIntervalSince(now) < PlanUsage.week {
            return date.formatted(style.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(style.day().month(.abbreviated))
    }

    static func percent(_ value: Double, locale: Locale) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }
}
