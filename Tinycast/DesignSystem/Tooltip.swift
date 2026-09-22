import SwiftUI

private enum TooltipLabel {
    case text(String)
    case keyCap(String)
}

/// A hover label in Tinycast's own vocabulary, replacing a system `.help()` tooltip.
private struct TooltipModifier: ViewModifier {
    let label: TooltipLabel?
    let alignment: HorizontalAlignment
    let edge: VerticalEdge
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
            .overlay(alignment: Alignment(horizontal: alignment, vertical: side)) {
                if let label, visible { tile(label) }
            }
    }

    private var side: VerticalAlignment { edge == .top ? .top : .bottom }

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
            // A zero-height frame on the control's edge, so a label of any height hangs off it.
            .frame(height: 0, alignment: edge == .top ? .bottom : .top)
            .offset(y: edge == .top ? -metrics.spacing.sm : metrics.spacing.sm)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

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
    /// Align it against a side edge, and hang it `.bottom` from a control at the window's top.
    func tooltip(
        _ text: String?, alignment: HorizontalAlignment = .center, edge: VerticalEdge = .top
    ) -> some View {
        modifier(
            TooltipModifier(label: text.map(TooltipLabel.text), alignment: alignment, edge: edge))
    }

    func tooltip(keyCap: String?) -> some View {
        modifier(
            TooltipModifier(label: keyCap.map(TooltipLabel.keyCap), alignment: .center, edge: .top))
    }
}
