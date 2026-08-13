import SwiftUI

/// Deliberately not a focusable control. See docs/features/hotkeys.md#recorder.
struct ShortcutRecorder: View {
    let action: HotKeyAction
    /// Drops the empty well's *fill* when nothing is bound, for a recorder that repeats once per
    /// row: a column of identical filled pills reads louder than the commands it belongs to. The
    /// border stays either way — without it the control reads as dead text — and the fill returns on
    /// hover, while recording, and whenever there is a shortcut to show.
    var isQuiet = false

    @Environment(HotKeyManager.self) private var hotKeys
    /// Observed so a bound double-tap surfaces its warning the moment the grant changes.
    private var doubleTapMonitor: DoubleTapMonitor { hotKeys.doubleTapMonitor }
    @State private var hovered = false

    private var isRecording: Bool { hotKeys.recordingAction == action }

    /// A quiet recorder sits back a shade until it is pointed at, without going so faint that it
    /// stops reading as something you can press.
    private var unsetInk: Color {
        isRecording || !isQuiet || hovered
            ? Theme.Colors.textSecondary : Theme.Colors.textTertiary
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
        // The width is kept either way, so a column of recorders stays aligned as they fill in.
        let showsFill = !isQuiet || isRecording || hovered || hotKeys.binding(for: action) != nil
        content
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(width: Theme.Size.shortcutRecorder, height: 24)
            .background(shape.fill(Theme.Colors.cardFill).opacity(showsFill ? 1 : 0))
            .overlay(
                shape.strokeBorder(
                    isRecording ? Color.accentColor : Theme.Colors.cardStroke, lineWidth: 1)
            )
            // An over-long binding truncates rather than resizing the field.
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture { hotKeys.recordingAction = action }
            .onHover { hovered = $0 }
            // Hand the callout this field's bounds while it's the open one.
            .anchorPreference(key: ShortcutRecorderAnchorKey.self, value: .bounds) {
                isRecording ? $0 : nil
            }
            // Rows are lazy: a recording row scrolled away must release the session.
            .onDisappear { if isRecording { hotKeys.recordingAction = nil } }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }

    @ViewBuilder
    private var content: some View {
        if let binding = hotKeys.binding(for: action) {
            boundLabel(binding)
        } else {
            Text(isRecording ? "Listening…" : "Record")
                .font(Theme.Typography.keyCap)
                .foregroundStyle(unsetInk)
        }
    }

    private func boundLabel(_ binding: HotKeyBinding) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            // A double-tap binding is dead without the grant, so say so where the binding is.
            if binding.doubleTapModifier != nil, doubleTapMonitor.needsAccessibility {
                Button {
                    Permissions.openAccessibilitySettings()
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Double-tap shortcuts need Accessibility access. Click to grant it.")
            }
            ForEach(Array(binding.keycaps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .frame(
                        minWidth: Theme.Size.recorderKeyCap, minHeight: Theme.Size.recorderKeyCap
                    )
                    .background(
                        RoundedRectangle(
                            cornerRadius: Theme.Radius.recorderKeyCap, style: .continuous
                        )
                        .fill(Color.primary.opacity(0.08))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        // Overlaid, not a row member, so it costs the caps no width.
        .overlay(alignment: .trailing) {
            Button {
                hotKeys.setBinding(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
    }
}
