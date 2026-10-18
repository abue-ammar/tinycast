import SwiftUI

/// Bounds of the open recorder, so an ancestor outside the `ScrollView` can draw it.
struct ShortcutRecorderAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct ShortcutRecorderPopover: View {
    let placement: CalloutPlacement

    @Environment(HotKeyManager.self) private var hotKeys
    private var capture: ShortcutCaptureSession { hotKeys.capture }

    private struct State {
        let caps: [String]
        let label: String
        var isExample = false
        var tint: Color?
        var prefix: String?

        @MainActor static func binding(
            _ binding: HotKeyBinding, label: String, tint: Color? = nil
        )
            -> Self
        {
            Self(
                caps: binding.recorderKeycaps, label: label, tint: tint,
                prefix: binding.recorderPrefix)
        }
    }

    var body: some View {
        let state = self.state
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(state.caps.enumerated()), id: \.offset) { _, cap in
                    KeyCapChip(text: cap, scale: .hero, prefix: state.prefix)
                }
            }
            .frame(height: Theme.Size.heroKeyCap)
            .opacity(state.isExample ? 0.5 : 1)

            Text(state.label)
                .font(Theme.Typography.compactKeyCap)
                .foregroundStyle(state.tint ?? Theme.Colors.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
                .frame(height: Theme.Size.shortcutPopoverLine * 2)
        }
        .offset(y: Theme.Spacing.sm + 1)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .padding(placement.caretEdge == .top ? .top : .bottom, Theme.Size.calloutCaretHeight)
        .frame(
            width: Theme.Size.shortcutPopover.width, height: Theme.Size.shortcutPopover.height
        )
        .overlay(alignment: .topLeading) {
            KeyCapChip(text: String(localized: "esc"), scale: .compact)
                .opacity(0.7)
                .padding(.leading, Theme.Spacing.md)
                .padding(
                    .top,
                    Theme.Spacing.sm
                        + (placement.caretEdge == .top ? Theme.Size.calloutCaretHeight : 0))
        }
        .glassEffect(
            .regular, in: CalloutShape(caretEdge: placement.caretEdge, caretX: placement.caretX))
    }

    private var state: State {
        if let conflict = capture.conflict {
            return .binding(conflict.binding, label: conflict.owner, tint: .orange)
        }
        if let key = capture.awaitingSecondModifier {
            let secondPress = capture.heldModifier == key
            return .binding(
                secondPress ? key.doubleBinding : key.singleBinding,
                label: secondPress
                    ? String(localized: "Release to record")
                    : String(localized: "Press again for a double press"))
        }
        if let key = capture.heldModifier {
            return .binding(key.singleBinding, label: String(localized: "Release or complete the shortcut"))
        }
        let flags =
            capture.heldGlobe
            ? capture.heldModifiers.union(.function) : capture.heldModifiers
        let held = KeyShortcut.collapsedModifierSymbols(
            from: flags, hyperChord: KeyShortcut.displayedHyperChord())
        guard held.isEmpty else { return State(caps: held, label: String(localized: "Press another key")) }
        return State(
            caps: [DoubleTapModifier.option.glyph, "A"], label: String(localized: "Type a shortcut"),
            isExample: true)
    }
}

// MARK: - Host

/// Draws the open recorder's callout over the pane, where the pane's `ScrollView` can't clip it.
private struct ShortcutRecorderPopoverHost: ViewModifier {
    @Environment(HotKeyManager.self) private var hotKeys

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(ShortcutRecorderAnchorKey.self) { anchor in
            GeometryReader { proxy in
                ShortcutRecorderPopoverLayer(
                    placement: anchor.map { placement(field: proxy[$0], in: proxy.size) },
                    recordingAction: hotKeys.recordingAction)
            }
            // Informational: clicks fall through to the session's mouse monitor, which closes.
            .allowsHitTesting(false)
        }
    }

    private func placement(field: CGRect, in size: CGSize) -> CalloutPlacement {
        CalloutPlacement.resolve(
            field: field, container: size, size: Theme.Size.shortcutPopover,
            gap: Theme.Spacing.sm, inset: Theme.Spacing.xs,
            cornerRadius: Theme.Radius.menuPanel, caretWidth: Theme.Size.calloutCaretWidth)
    }
}

/// Retains the last anchor while the callout animates away from it.
private struct ShortcutRecorderPopoverLayer: View {
    let placement: CalloutPlacement?
    let recordingAction: HotKeyAction?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presentedPlacement: CalloutPlacement?
    @State private var isVisible = false

    var body: some View {
        Color.clear.overlay {
            if let presentedPlacement {
                ShortcutRecorderPopover(placement: presentedPlacement)
                    .scaleEffect(
                        isVisible ? 1 : 0.5, anchor: scaleAnchor(for: presentedPlacement)
                    )
                    .opacity(isVisible ? 1 : 0)
                    .position(presentedPlacement.center)
            }
        }
        .onChange(of: placement, initial: true) { _, placement in
            guard let placement, recordingAction != nil else { return }
            present(at: placement)
        }
        .onChange(of: recordingAction, initial: true) { _, recordingAction in
            if recordingAction == nil {
                withAnimation(exitAnimation) { isVisible = false }
            } else if let placement {
                present(at: placement)
            }
        }
        .task(id: isVisible) {
            guard !isVisible, presentedPlacement != nil else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(Theme.Duration.exit))
            }
            guard !Task.isCancelled, !isVisible else { return }
            presentedPlacement = nil
        }
    }

    private var entryAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: Theme.Duration.enter)
    }

    private var exitAnimation: Animation? {
        reduceMotion ? nil : .easeIn(duration: Theme.Duration.exit)
    }

    private func present(at placement: CalloutPlacement) {
        presentedPlacement = placement
        guard !isVisible else { return }
        Task { @MainActor in
            await Task.yield()
            guard recordingAction != nil, presentedPlacement == placement else { return }
            withAnimation(entryAnimation) { isVisible = true }
        }
    }

    private func scaleAnchor(for placement: CalloutPlacement) -> UnitPoint {
        placement.caretEdge == .bottom ? .bottom : .top
    }
}

extension View {
    func shortcutRecorderPopoverHost() -> some View {
        modifier(ShortcutRecorderPopoverHost())
    }
}
