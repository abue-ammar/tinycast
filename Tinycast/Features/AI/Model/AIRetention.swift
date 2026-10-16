import Foundation

/// Days as the raw value, `forever` negative so the 0 an unset key reads matches no case at all.
enum AIRetention: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case threeMonths = 90
    case forever = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .week: return String(localized: "7 Days")
        case .month: return String(localized: "30 Days")
        case .threeMonths: return String(localized: "3 Months")
        case .forever: return String(localized: "Forever")
        }
    }

    /// The instant before which a conversation is too old to keep, or `nil` when nothing expires.
    func cutoff(from now: Date) -> Date? {
        self == .forever ? nil : now.addingTimeInterval(-TimeInterval(rawValue) * 86_400)
    }
}
