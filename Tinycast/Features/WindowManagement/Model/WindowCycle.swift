import Foundation

/// What a repeat press of a half does. docs/features/window-management.md#cycling-and-restore
enum WindowCycle: String, CaseIterable, Identifiable, Sendable {
    case off
    case sizes
    /// Walk the half one slot along the strip of half-slots every display contributes.
    case displays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "None"
        case .sizes: "Cycle ½, ⅓ and ⅔"
        case .displays: "Cycle displays"
        }
    }

    var detail: String {
        switch self {
        case .off: "Repeating a half keeps the same frame."
        case .sizes: "Repeating a half steps through ⅓ and ⅔."
        case .displays: "Repeating a half moves it across your displays."
        }
    }
}
