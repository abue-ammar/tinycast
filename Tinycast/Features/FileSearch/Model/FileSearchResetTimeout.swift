import Foundation

enum FileSearchResetTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterOneMinute = 60
    case afterTwoMinutes = 120
    case afterThreeMinutes = 180
    case afterFiveMinutes = 300
    case never = -1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .afterOneMinute: "After 1 minute"
        case .afterTwoMinutes: "After 2 minutes"
        case .afterThreeMinutes: "After 3 minutes"
        case .afterFiveMinutes: "After 5 minutes"
        case .never: "Never"
        }
    }

    var interval: TimeInterval {
        self == .never ? .infinity : TimeInterval(rawValue)
    }
}
