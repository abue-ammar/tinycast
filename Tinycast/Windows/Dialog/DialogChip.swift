import SwiftUI

/// Our own choice: a menu-style `Picker` drops an AppKit popover onto a vibrancy surface.
struct DialogChip: View {
    @Environment(\.metrics) private var metrics
    let title: String
    let selected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Theme.Colors.controlSurface
    }

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(selected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .padding(.horizontal, metrics.spacing.lg)
                .frame(height: metrics.size.barButtonHeight)
                .contentShape(Capsule())
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
