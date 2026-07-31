import SwiftUI

/// A small hover-triggered label in Tinycast's own dark vocabulary, standing in for a
/// system `.help()` tooltip on the modal's borderless panel.
private struct TooltipModifier: ViewModifier {
    let text: String?
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .onHover { hovered = text != nil && $0 }
            .overlay(alignment: .top) {
                if let text, hovered {
                    Text(text)
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(Capsule().fill(Theme.Colors.controlSurface))
                        .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
                        .fixedSize()
                        .offset(y: -Theme.Spacing.xxl)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: Theme.Duration.tooltip), value: hovered)
    }
}

extension View {
    /// Hover label matching the palette's own keycap-chip styling, used where a system
    /// `.help()` tooltip would look out of place on Tinycast's own chrome.
    func tooltip(_ text: String?) -> some View {
        modifier(TooltipModifier(text: text))
    }
}
