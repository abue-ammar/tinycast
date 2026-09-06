import SwiftUI

/// `DialogButton`'s twin, duplicated so the camera's controls need not move with a dialog's.
struct CameraButton: View {
    /// Secondary also reads as "off": the mirror toggle dims rather than growing a second style.
    enum Emphasis {
        case primary
        case secondary
    }

    let title: String
    var keyCap: String?
    var emphasis: Emphasis = .primary
    let onActivate: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onActivate) {
            Text(title)
                .font(Theme.Typography.bar)
                .foregroundStyle(
                    emphasis == .primary ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
                )
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(height: Theme.Size.menuButton)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Capsule())
        .tooltip(keyCap)
    }
}
