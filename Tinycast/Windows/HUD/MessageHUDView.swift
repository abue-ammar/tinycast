import SwiftUI

/// The message pill, whose trailing mark is its tone or a spinner. See docs/ui.md#dialogs--hud.
struct MessageHUDView: View {
    /// A report ends with its tone's glyph; something still running ends with a spinner instead.
    enum Accessory {
        case tone(DialogTone)
        case progress
    }

    let message: String
    let accessory: Accessory
    var onCancel: (() -> Void)? = nil
    @State private var hovered = false

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

    private var content: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(message)
                .font(Theme.Typography.bar)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            mark
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .frame(maxWidth: Theme.Size.hudMaxWidth, alignment: .leading)
        .fixedSize()
        // Not glass: with nothing to lens it falls back to an opaque backing and shows.
        .background(hovered ? Theme.Colors.controlHover : Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(hovered ? Theme.Colors.border : Color.clear, lineWidth: 1)
        )
    }

    /// One box for both marks, so swapping a spinner for its outcome cannot resize the pill.
    private var mark: some View {
        Group {
            if hovered, onCancel != nil {
                Image(systemName: "xmark")
                    .font(Theme.Typography.menuIcon.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                    .transition(.opacity)
            } else {
                symbol
                    .font(Theme.Typography.menuIcon)
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch accessory {
        case .tone(let tone):
            Image(systemName: tone.hudSymbol)
                .symbolRenderingMode(.hierarchical)
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
        case .neutral: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .danger: return "exclamationmark.circle.fill"
        }
    }
}
