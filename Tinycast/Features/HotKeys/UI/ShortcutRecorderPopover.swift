import SwiftUI

/// Bounds of the open recorder, so an ancestor outside the `ScrollView` can draw it.
struct ShortcutRecorderAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// The callout above the field: what to press, what is held, or what is in the way.
struct ShortcutRecorderPopover: View {
    let placement: CalloutPlacement

    @Environment(HotKeyManager.self) private var hotKeys
    private var capture: ShortcutCaptureSession { hotKeys.capture }

    private struct State {
        let caps: [String]
        let label: String
        var isExample = false
        var tint: Color?
    }

    var body: some View {
        let state = self.state
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(state.caps.enumerated()), id: \.offset) { _, cap in
                    KeyCapChip(text: cap, scale: .hero)
                }
            }
            .frame(height: Theme.Size.heroKeyCap)
            .opacity(state.isExample ? 0.5 : 1)

            Text(state.label)
                .font(Theme.Typography.compactKeyCap)
                .foregroundStyle(state.tint ?? Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: Theme.Size.shortcutPopoverLine)

            KeyCapChip(text: "esc", scale: .compact)
                .opacity(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .padding(placement.caretEdge == .top ? .top : .bottom, Theme.Size.calloutCaretHeight)
        .frame(
            width: Theme.Size.shortcutPopover.width, height: Theme.Size.shortcutPopover.height
        )
        // Stock glass owns its elevation, as in `PopoverMenu` — no hand-tuned shadow.
        .glassEffect(
            .regular, in: CalloutShape(caretEdge: placement.caretEdge, caretX: placement.caretX))
    }

    private var state: State {
        if let conflict = capture.conflict {
            return State(caps: conflict.binding.keycaps, label: conflict.owner, tint: .orange)
        }
        let held = KeyShortcut.collapsedModifierSymbols(
            from: capture.heldModifiers, hyperChord: KeyShortcut.displayedHyperChord())
        guard held.isEmpty else { return State(caps: held, label: "Add a key") }
        return State(
            caps: [DoubleTapModifier.option.glyph, "A"], label: "Type a shortcut", isExample: true)
    }
}

// MARK: - Host

/// Draws the open recorder's callout over the pane, where the pane's `ScrollView` can't clip it.
private struct ShortcutRecorderPopoverHost: ViewModifier {
    @Environment(HotKeyManager.self) private var hotKeys

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ShortcutRecorderAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, hotKeys.recordingAction != nil {
                    callout(field: proxy[anchor], in: proxy.size)
                }
            }
            // Informational: clicks fall through to the session's mouse monitor, which closes.
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.14), value: hotKeys.recordingAction)
        }
    }

    private func callout(field: CGRect, in size: CGSize) -> some View {
        let placement = CalloutPlacement.resolve(
            field: field, container: size, size: Theme.Size.shortcutPopover,
            gap: Theme.Spacing.sm, inset: Theme.Spacing.xs,
            cornerRadius: Theme.Radius.menuPanel, caretWidth: Theme.Size.calloutCaretWidth)

        return ShortcutRecorderPopover(placement: placement)
            .position(placement.center)
            .transition(
                .opacity.combined(
                    with: .scale(0.96, anchor: placement.caretEdge == .bottom ? .bottom : .top)))
    }
}

extension View {
    /// Hosts the shortcut recorder's callout for every recorder inside this view.
    func shortcutRecorderPopoverHost() -> some View {
        modifier(ShortcutRecorderPopoverHost())
    }
}
