import CoreGraphics
import Foundation

enum FileSearchPreviewSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small (120 pt)"
        case .medium: "Medium (180 pt)"
        case .large: "Large (240 pt)"
        case .extraLarge: "Extra Large (300 pt)"
        }
    }

    var maxHeight: CGFloat {
        switch self {
        case .small: 120
        case .medium: 180
        case .large: 240
        case .extraLarge: 300
        }
    }

    var placeholderIconSize: CGFloat {
        switch self {
        case .small: 32
        case .medium: 44
        case .large: 56
        case .extraLarge: 68
        }
    }
}
