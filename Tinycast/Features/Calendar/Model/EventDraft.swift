import Foundation

/// What the Create Event prompt collects, before anything touches the calendar.
struct EventDraft: Sendable, Equatable {
    var title: String = ""
    var startOffsetMinutes: Int = 0
    var durationMinutes: Int = 30

    static let startOffsets = [0, 15, 30, 60]
    static let durations = [15, 30, 45, 60]

    /// A blank title is the one thing that cannot be written; everything else has a default.
    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    func start(from now: Date) -> Date {
        now.addingTimeInterval(TimeInterval(startOffsetMinutes * 60))
    }

    func end(from now: Date) -> Date {
        start(from: now).addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    static func label(startOffset minutes: Int, locale: Locale) -> String {
        minutes == 0 ? String(localized: "Now", locale: locale) : label(duration: minutes, locale: locale)
    }

    static func label(duration minutes: Int, locale: Locale) -> String {
        Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
    }
}
