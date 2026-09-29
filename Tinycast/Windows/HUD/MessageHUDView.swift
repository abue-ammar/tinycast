import SwiftUI

/// The message pill, led by its tone's mark or a spinner. See docs/ui.md#dialogs--hud.
struct MessageHUDView: View {
    enum Accessory {
        case tone(DialogTone)
        case progress
    }

    private static let glowOpacity = 0.14
    private static let glowRadius: CGFloat = 150
    private static let rimOpacity = 0.25

    let message: String
    let accessory: Accessory
    var onCancel: (() -> Void)? = nil
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        Group {
            if let onCancel {
                Button(action: onCancel) {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel \(message)")
            } else {
                content
            }
        }
        .onHover { isHovered in
            if onCancel != nil {
                withAnimation(.easeOut(duration: Theme.Duration.hover)) {
                    hovered = isHovered
                }
            }
        }
    }

    private var tint: Color {
        switch accessory {
        case .tone(let tone): tone.tint
        case .progress: Theme.Colors.progress
        }
    }

    private var content: some View {
        HStack(spacing: metrics.spacing.md) {
            mark
            Text(message)
                .font(metrics.typography.bar)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.lg)
        .frame(maxWidth: metrics.size.hudMaxWidth, alignment: .leading)
        .fixedSize()
        .background { glow }
        // Not glass: with nothing to lens it falls back to an opaque backing and shows.
        .background(hovered ? Theme.Colors.controlHover : Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(Capsule())
        .overlay { rim }
    }

    private var glow: some View {
        GeometryReader { proxy in
            Capsule().fill(
                RadialGradient(
                    colors: [tint.opacity(Self.glowOpacity), tint.opacity(0.03), .clear],
                    center: UnitPoint(
                        x: (metrics.spacing.xl + metrics.size.menuIcon / 2) / proxy.size.width,
                        y: 0.5),
                    startRadius: 0, endRadius: Self.glowRadius))
        }
    }

    private var rim: some View {
        Capsule().strokeBorder(
            hovered
                ? AnyShapeStyle(Theme.Colors.border)
                : AnyShapeStyle(
                    LinearGradient(
                        colors: [tint.opacity(Self.rimOpacity), tint.opacity(0.06), .clear],
                        startPoint: .leading, endPoint: .trailing)),
            lineWidth: Theme.Size.hairline)
    }

    /// One box for both marks, so swapping a spinner for its outcome cannot resize the pill.
    private var mark: some View {
        Group {
            if hovered, onCancel != nil {
                Image(systemName: "xmark")
                    .font(metrics.typography.menuIcon.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    .transition(.opacity)
            } else {
                symbol
                    .font(metrics.typography.menuIcon)
                    .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch accessory {
        case .tone(let tone):
            Image(systemName: tone.hudSymbol)
                .foregroundStyle(tone.tint)
        case .progress:
            // A `ProgressView` spinner is drawn by AppKit and ignores every tint it is given.
            Image(systemName: "progress.indicator")
                .foregroundStyle(Theme.Colors.progress)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
        }
    }
}

/// File-scoped on purpose, so nothing can reach for it when building a dialog.
extension DialogTone {
    fileprivate var hudSymbol: String {
        switch self {
        case .neutral: return "info"
        case .success: return "checkmark"
        case .danger: return "exclamationmark"
        }
    }
}
