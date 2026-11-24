import SwiftUI

extension PlanUsage.Level {
    var tint: Color {
        switch self {
        case .normal: return Theme.Colors.success
        case .high: return Theme.Colors.warning
        case .critical: return Theme.Colors.destructive
        }
    }

    var nsTint: NSColor { NSColor(tint) }
}
