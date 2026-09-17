import SwiftUI

private enum TooltipLabel {
    case text(String)
    case keyCap(String)
}

/// A hover label in Tinycast's own vocabulary, replacing a system `.help()` tooltip.
private struct TooltipModifier: ViewModifier {
    let label: TooltipLabel?
    @Environment(\.metrics) private var metrics
    @State private var hovered = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onHover {
                hovered = label != nil && $0
                if !hovered { visible = false }
            }
            .task(id: hovered) {
                guard hovered else { return }
                try? await Task.sleep(for: .seconds(Theme.Duration.tooltipDelay))
                guard !Task.isCancelled, hovered else { return }
                withAnimation(.easeOut(duration: Theme.Duration.tooltip)) { visible = true }
            }
            .overlay(alignment: .top) {
                if let label, visible { tile(label) }
            }
    }

    private func tile(_ label: TooltipLabel) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.tooltip, style: .continuous)
        return chip(label)
            .padding(metrics.spacing.xs)
            .background {
                shape.fill(Color(nsColor: .windowBackgroundColor))
                shape.fill(Theme.Colors.controlSurface)
            }
            .shadow(
                color: Theme.Colors.tooltipShadow, radius: metrics.spacing.xs,
                y: metrics.spacing.xxs
            )
            .fixedSize()
            .offset(y: -(tileHeight + metrics.spacing.sm))
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    /// Both forms seat their content in one cap-sized row, so the clearance is a constant.
    private var tileHeight: CGFloat { metrics.size.keyCap + metrics.spacing.xs * 2 }

    @ViewBuilder private func chip(_ label: TooltipLabel) -> some View {
        switch label {
        case .text(let text):
            Text(text)
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, metrics.spacing.xs)
                .frame(minHeight: metrics.size.keyCap)
        case .keyCap(let cap):
            KeyCapChip(text: cap, style: .outline)
        }
    }
}

extension View {
    /// What a control does, or — in the `keyCap` form — the shortcut it answers to.
    func tooltip(_ text: String?) -> some View {
        modifier(TooltipModifier(label: text.map(TooltipLabel.text)))
    }

    func tooltip(keyCap: String?) -> some View {
        modifier(TooltipModifier(label: keyCap.map(TooltipLabel.keyCap)))
    }
}
