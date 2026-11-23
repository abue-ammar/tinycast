import Foundation

enum IconStyle: String, CaseIterable, Identifiable, Sendable {
    case system
    case colorful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .colorful: String(localized: "Colorful")
        }
    }
}
