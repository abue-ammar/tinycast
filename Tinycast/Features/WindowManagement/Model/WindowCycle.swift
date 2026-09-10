import Foundation

/// What a repeat press of a half does. docs/features/window-management.md#cycling-and-restore
enum WindowCycle: String, CaseIterable, Identifiable, Sendable {
    /// Re-apply the same half — the shortcut is idempotent.
    case off
    /// Step the half through ⅓ and ⅔ before it returns to ½.
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
        case .off: "Triggering a half again re-applies the same frame."
        case .sizes: "Triggering a half again steps it through a third and two thirds."
        case .displays:
            "Triggering a half again walks it to the next half across your displays, wrapping around."
        }
    }
}
