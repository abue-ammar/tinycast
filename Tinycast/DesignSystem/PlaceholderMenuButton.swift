import SwiftUI

/// A form field's placeholder menu, drawn like the forms' other menus so it reads as one.
struct PlaceholderMenuButton: View {
    let isOpen: Bool
    @Binding var frame: CGRect
    let action: () -> Void

    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.spacing.xs) {
                Text("Insert Placeholder")
                Image(systemName: "chevron.down")
                    .font(metrics.typography.disclosure)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            frame = $0
        }
    }
}
