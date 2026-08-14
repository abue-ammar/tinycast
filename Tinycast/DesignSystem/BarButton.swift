import SwiftUI

/// A bar control's hover chrome. The footer's buttons are capsules; one that opens a menu takes
/// that menu's own corner instead, so the control and what it opens read as one piece.
enum BarButtonChrome {
    case capsule
    case menu

    var shape: AnyShape {
        switch self {
        case .capsule:
            return AnyShape(Capsule())
        case .menu:
            return AnyShape(
                RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous))
        }
    }
}

/// A palette bar control: bare label at rest, a faint fill on hover.
/// Hover lives here, so a sweep across one never re-renders the view that owns it.
struct BarButton<Label: View>: View {
    var chrome: BarButtonChrome = .capsule
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        let shape = chrome.shape
        return Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: Theme.Size.barButtonHeight)
                .contentShape(shape)
                .background(shape.fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
