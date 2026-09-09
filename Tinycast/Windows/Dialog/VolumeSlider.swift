import SwiftUI

/// Our own slider: `NSSlider` would drop an Aqua control onto a vibrancy surface.
struct VolumeSlider: View {
    @Environment(\.locale) private var localizationLocale
    let state: VolumeState

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: VolumeLevel.symbol(level: state.level))
                .font(Theme.Typography.menuIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.menuIcon)
            GeometryReader { geometry in
                let width = geometry.size.width
                let travel = max(width - Theme.Size.volumeKnob, 1)
                let clamped = VolumeLevel.clamped(state.level)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.controlSurface)
                        .frame(height: Theme.Size.volumeTrackHeight)
                    Capsule()
                        .fill(Theme.Colors.textPrimary.opacity(0.85))
                        .frame(
                            width: Theme.Size.volumeKnob / 2 + clamped * travel,
                            height: Theme.Size.volumeTrackHeight)
                    Circle()
                        .fill(Theme.Colors.textPrimary)
                        .frame(width: Theme.Size.volumeKnob, height: Theme.Size.volumeKnob)
                        .offset(x: clamped * travel)
                }
                .frame(height: Theme.Size.volumeKnob)
                // minimumDistance 0, so a plain click jumps the level like a native track.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let position = (value.location.x - Theme.Size.volumeKnob / 2) / travel
                            state.level = VolumeLevel.clamped(position)
                        }
                )
            }
            .frame(height: Theme.Size.volumeKnob)
            Text(VolumeLevel.percentage(state.level))
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .frame(width: Theme.Size.volumeReadout, alignment: .trailing)
        }
    }
}
