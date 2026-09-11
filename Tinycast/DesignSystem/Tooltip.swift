import SwiftUI

/// A hover label in Tinycast's own vocabulary, replacing a system `.help()` tooltip.
private struct TooltipModifier: ViewModifier {
    let text: String?
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        content
            .onHover { hovered = text != nil && $0 }
            .overlay(alignment: .top) {
                if let text, hovered {
                    Text(text)
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, metrics.spacing.sm)
                        .padding(.vertical, metrics.spacing.xxs)
                        .background(Capsule().fill(Theme.Colors.controlSurface))
                        .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
                        .fixedSize()
                        .offset(y: -metrics.spacing.xxl)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: Theme.Duration.tooltip), value: hovered)
    }
}

extension View {
    /// Hover label styled like the palette's keycap chips, for our own chrome.
    func tooltip(_ text: String?) -> some View {
        modifier(TooltipModifier(text: text))
    }
}
