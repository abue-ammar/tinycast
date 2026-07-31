import SwiftUI

/// A Tinycast dialog: the palette's surface recipe (scrim over vibrancy, clipped last) at modal size, with glass only on the buttons.
struct TinycastModalView: View {
    let request: ModalRequest
    @ObservedObject var volume: ModalWindowController.VolumeState
    let onChoose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                Image(systemName: request.symbol ?? request.kind.defaultSymbol)
                    .font(.system(size: Theme.Size.modalIcon, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(request.kind.tint)
                    .frame(width: Theme.Size.modalIcon)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(request.title)
                        .font(.headline)
                    if let message = request.message {
                        Text(message)
                            .font(Theme.Typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if request.showsVolumeSlider {
                VolumeSlider(level: $volume.level)
            }

            HStack(spacing: Theme.Spacing.md) {
                Spacer(minLength: 0)
                ForEach(visualOrder, id: \.self) { index in
                    ModalButton(
                        action: request.actions[index],
                        kind: request.kind,
                        keyCap: keyCap(for: index),
                        onActivate: { onChoose(index) }
                    )
                }
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.modalWidth, alignment: .leading)
        .background(Color.black.opacity(Theme.Colors.panelDimming))
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.modal, style: .continuous))
    }

    /// Cancel renders leading, matching macOS convention and the panel's Escape/Return keys, while `onChoose(index)` still dispatches against `request.actions`' original order so callers never have to think about display position.
    private var visualOrder: [Int] {
        request.actions.indices.sorted { rank(of: $0) < rank(of: $1) }
    }

    private func rank(of index: Int) -> Int {
        request.actions[index].role == .cancel ? 0 : 1
    }

    /// Only the two keys the panel actually handles are advertised, so a hover tooltip can't drift from the behavior.
    private func keyCap(for index: Int) -> String? {
        if index == request.defaultIndex { return "↵" }
        if index == request.cancelIndex { return "esc" }
        return nil
    }
}

private struct ModalButton: View {
    let action: ModalAction
    let kind: ModalKind
    let keyCap: String?
    let onActivate: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onActivate) {
            Text(action.title)
                .font(Theme.Typography.bar)
                .foregroundStyle(action.role == .cancel ? Theme.Colors.textSecondary : kind.tint)
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(height: Theme.Size.menuButton)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.menuHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frosted(in: Capsule())
        .tooltip(keyCap)
    }
}

/// Tinycast's own slider, because `NSSlider` would drop an Aqua control onto a surface whose whole vocabulary is white-alpha over vibrancy.
struct VolumeSlider: View {
    @Binding var level: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: level == 0 ? "speaker.slash.fill" : "speaker.fill")
                .font(Theme.Typography.menuIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Theme.Size.menuIcon)
            GeometryReader { geometry in
                let width = geometry.size.width
                let travel = max(width - Theme.Size.volumeKnob, 1)
                let clamped = min(max(level, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.controlSurface)
                        .frame(height: Theme.Size.volumeTrackHeight)
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(
                            width: Theme.Size.volumeKnob / 2 + clamped * travel,
                            height: Theme.Size.volumeTrackHeight)
                    Circle()
                        .fill(Color.white)
                        .frame(width: Theme.Size.volumeKnob, height: Theme.Size.volumeKnob)
                        .offset(x: clamped * travel)
                }
                .frame(height: Theme.Size.volumeKnob)
                // minimumDistance 0 so a plain click jumps the level, matching how a native slider's track behaves.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let position = (value.location.x - Theme.Size.volumeKnob / 2) / travel
                            level = min(max(position, 0), 1)
                        }
                )
            }
            .frame(height: Theme.Size.volumeKnob)
            Text(Self.percentage(level))
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                // A fixed slot keeps the track from resizing as the number grows from 0% to 100%.
                .frame(width: Theme.Size.rowIcon * 2, alignment: .trailing)
        }
    }

    static func percentage(_ level: Double) -> String {
        "\(Int((min(max(level, 0), 1) * 100).rounded()))%"
    }
}

/// The transient volume readout shown after a volume or mute command, since macOS only draws its own HUD for real media keys. A success/info confirmation for every other command is `HUDWindowController`'s pill instead, not this box, because that one has an actual level to show. Glass, because it is a floating control rather than a surface with content.
struct VolumeHUDView: View {
    @ObservedObject var state: ModalWindowController.VolumeState

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: symbol)
                .font(.system(size: Theme.Size.modalIcon, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.primary)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.controlSurface)
                Capsule()
                    .fill(Color.white.opacity(state.muted ? 0.35 : 0.85))
                    .frame(width: fill(level: state.muted ? 0 : state.level))
            }
            .frame(height: Theme.Size.volumeTrackHeight)
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.hudWidth, height: Theme.Size.hudHeight)
        .frosted(in: RoundedRectangle(cornerRadius: Theme.Radius.modal, style: .continuous))
    }

    private var symbol: String {
        if state.muted || state.level == 0 { return "speaker.slash.fill" }
        return state.level < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"
    }

    private func fill(level: Double) -> CGFloat {
        let track = Theme.Size.hudWidth - Theme.Spacing.xxl * 2
        return track * min(max(level, 0), 1)
    }
}
