import Foundation

/// What the Create Event prompt collects, before anything touches the calendar.
struct EventDraft: Sendable, Equatable {
    var title: String = ""
    /// How long from now the event starts; 0 is "Now".
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

    static func label(startOffset minutes: Int) -> String {
        minutes == 0 ? "Now" : label(duration: minutes)
    }

    static func label(duration minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr"
    }
}
