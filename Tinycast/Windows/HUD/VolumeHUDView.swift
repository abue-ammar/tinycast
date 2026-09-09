import SwiftUI

/// The volume box: glyph, bar, number, on the palette's surface recipe rather than glass.
struct VolumeHUDView: View {
    @Environment(\.locale) private var localizationLocale
    let state: VolumeState

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SymbolImage(
                name: VolumeLevel.symbol(level: state.level, muted: state.muted),
                size: Theme.Size.dialogIcon
            )
            .foregroundStyle(Color.primary)
            HStack(spacing: Theme.Spacing.md) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.Colors.controlSurface)
                        Capsule()
                            .fill(Theme.Colors.textPrimary.opacity(state.muted ? 0.35 : 0.85))
                            .frame(width: geometry.size.width * fill)
                    }
                }
                .frame(height: Theme.Size.volumeTrackHeight)
                // Muted prints the word: the bar is empty, and a number would contradict it.
                Text(state.muted ? String(localized: "Muted", bundle: .appLanguage) : VolumeLevel.percentage(state.level))
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
                    .frame(width: Theme.Size.volumeReadout, alignment: .trailing)
            }
        }
        // Asymmetric: side padding costs far more on a 200pt box than a 420pt dialog.
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(width: Theme.Size.hudWidth, height: Theme.Size.hudHeight)
        .background(Theme.Colors.panelScrim)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        .panelEntrance()
        // A repeat command slides the bar to its new value instead of cutting to it.
        .animation(.easeOut(duration: Theme.Duration.exit), value: state.level)
        .animation(.easeOut(duration: Theme.Duration.exit), value: state.muted)
    }

    private var fill: CGFloat {
        state.muted ? 0 : VolumeLevel.clamped(state.level)
    }
}
