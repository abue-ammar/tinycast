import SwiftUI

struct MonitorHUDView: View {
    let state: MonitorHUDController.State

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            SymbolImage(name: state.symbol, size: Theme.Size.dialogIcon)
                .foregroundStyle(Theme.Colors.textPrimary)
            ProgressView(value: state.level)
                .tint(Theme.Colors.textPrimary)
                .accessibilityLabel(state.name)
                .accessibilityValue(state.label)
            Text(state.label)
                .font(Theme.Typography.rowTrailing)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(width: Theme.Size.hudWidth, height: Theme.Size.hudHeight)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .animation(.easeOut(duration: Theme.Duration.exit), value: state.level)
    }
}
