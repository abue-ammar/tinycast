import SwiftUI

struct MonitorHUDView: View {
    @Environment(\.metrics) private var metrics
    let state: MonitorHUDController.State

    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            SymbolImage(name: state.symbol, size: metrics.size.dialogIcon)
                .foregroundStyle(Theme.Colors.textPrimary)
            ProgressView(value: state.level)
                .tint(Theme.Colors.textPrimary)
                .accessibilityLabel(state.name)
                .accessibilityValue(state.label)
            Text(state.label)
                .font(metrics.typography.rowTrailing)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, metrics.spacing.xxl)
        .padding(.horizontal, metrics.spacing.xl)
        .frame(width: metrics.size.hudWidth, height: metrics.size.hudHeight)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.dialog, style: .continuous))
        .animation(.easeOut(duration: Theme.Duration.exit), value: state.level)
    }
}
