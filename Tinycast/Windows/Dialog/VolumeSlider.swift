import SwiftUI

struct VolumeSlider: View {
    @Environment(\.metrics) private var metrics
    let state: VolumeState

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Image(systemName: VolumeLevel.symbol(level: state.level))
                .font(metrics.typography.menuIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: metrics.size.menuIcon)
            Slider(value: level, in: 0...1)
                .labelsHidden()
                .tint(Theme.Colors.textPrimary)
                .accessibilityLabel("Output volume")
            Text(VolumeLevel.percentage(state.level))
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .frame(width: metrics.size.volumeReadout, alignment: .trailing)
        }
    }

    private var level: Binding<Double> {
        Binding(
            get: { state.level },
            set: { state.level = VolumeLevel.clamped($0) })
    }
}
