import SwiftUI

struct OnboardingShortcutView: View {
    private typealias Keycap = Theme.Onboarding.Keycap
    private static let spaceGlyph = "␣"

    let session: OnboardingShortcutSession
    let confirmed: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @State private var heldModifiers: SwiftUI.EventModifiers = []
    @State private var hoveringShortcut = false

    private var binding: HotKeyBinding { session.binding }
    private var isRecording: Bool { session.isRecording }

    var body: some View {
        @Bindable var settings = settings
        let notice = session.notice
        VStack(spacing: Theme.Spacing.xxxl) {
            OnboardingSetupPages.Header(
                title: session.isReady ? "Try Your Shortcut" : "Set Up Your Launcher"
            ) {
                if session.isReady {
                    Text("Press this shortcut to open Tinycast.")
                        .foregroundStyle(.secondary)
                }
            }
            shortcutButton
            if let notice {
                ShortcutNotice(
                    notice: notice, session: session,
                    keys: Text(verbatim: binding.keycaps.joined(separator: " ")).bold()
                )
                .disabled(confirmed)
            }
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(confirmed)
                .padding(.top, notice == nil ? 0 : Theme.Spacing.md)
        }
        .multilineTextAlignment(.center)
        .onModifierKeysChanged { _, held in heldModifiers = held }
        .onChange(of: appearsActive) { _, active in
            if active { refreshAvailability() } else { heldModifiers = [] }
        }
        .onChange(of: session.assignedBinding, initial: true) {
            heldModifiers = []
            refreshAvailability()
        }
        .onChange(of: isRecording) { _, recording in
            if !recording { heldModifiers = [] }
        }
        .onDisappear { if isRecording { hotKeys.recordingAction = nil } }
    }

    private var shortcutButton: some View {
        let hoverShape = RoundedRectangle(cornerRadius: Theme.Radius.menuPanel)
        let showsHover = hoveringShortcut && !confirmed && !isRecording
        let hoverAnimation: Animation? =
            settings.animationsEnabled && !reduceMotion ? .easeOut(duration: Theme.Duration.hover) : nil
        return Button {
            if isRecording {
                hotKeys.recordingAction = nil
            } else {
                hotKeys.startRecording(.togglePalette, checkingExternalConflicts: true)
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                keys(scale: 1)
                keys(scale: Keycap.compactScale)
                keys(scale: Keycap.smallestScale)
            }
            .padding(Keycap.hoverInset)
            .background {
                hoverShape.fill(Theme.Colors.rowHover)
                    .opacity(showsHover ? 1 : 0)
                    .animation(hoverAnimation, value: showsHover)
            }
            .contentShape(hoverShape)
            .onHover { hoveringShortcut = $0 }
        }
        .buttonStyle(.plain)
        .disabled(confirmed)
        .padding(-Keycap.hoverInset)
        .accessibilityLabel("Record Hotkey")
        .accessibilityValue(Text(verbatim: binding.keycaps.joined(separator: " ")))
        .background {
            if isRecording { ShortcutRecorderHitRegion(capture: hotKeys.capture) }
        }
        .anchorPreference(key: ShortcutRecorderAnchorKey.self, value: .bounds) {
            isRecording ? $0 : nil
        }
    }

    private func refreshAvailability() {
        guard !confirmed else { return }
        session.refresh()
    }

    private func keys(scale: CGFloat) -> some View {
        let caps = binding.recorderKeycaps
        let space = String(localized: "Space")
        let unit = Keycap.size * scale
        return HStack(spacing: unit * Keycap.gap) {
            ForEach(caps.indices, id: \.self) { index in
                let cap = caps[index]
                key(
                    cap, isSpace: cap == space, scale: scale,
                    pressed: confirmed || isHeld(cap, at: index, count: caps.count))
            }
        }
        .fixedSize()
        .background {
            RoundedRectangle(cornerRadius: unit * Keycap.glowCornerRadius)
                .fill(Keycap.glow)
                .padding(-unit * Keycap.glowSpread)
                .blur(radius: unit * Keycap.glowBlur)
                .allowsHitTesting(false)
        }
    }

    private func key(_ cap: String, isSpace: Bool, scale: CGFloat, pressed: Bool) -> some View {
        let unit = Keycap.size * scale
        let legend = keyLegend(cap)
        let width = unit * widthRatio(of: cap, isSpace: isSpace, hasLegend: legend != nil)
        let lift = unit * (pressed ? Keycap.pressedLift : Keycap.restingLift)
        let shape = RoundedRectangle(cornerRadius: unit * Keycap.cornerRadius, style: .continuous)
        let motion = pressed ? Keycap.press : Keycap.release
        return ZStack(alignment: .bottom) {
            shape.fill(Keycap.base)
                .frame(height: unit + lift)
                .shadow(
                    color: .black.opacity(
                        pressed ? Keycap.pressedShadowOpacity : Keycap.restingShadowOpacity),
                    radius: unit * Keycap.shadowRadius, y: unit * Keycap.shadowOffset)

            keyLabel(isSpace ? Self.spaceGlyph : cap, legend: legend, unit: unit)
                .foregroundStyle(Keycap.ink)
                .frame(width: width, height: unit)
                .background(Keycap.face, in: shape)
                .overlay { shape.strokeBorder(Keycap.rim, lineWidth: unit * Keycap.rimWidth) }
                .offset(y: -lift)
        }
        .frame(width: width, height: unit * Keycap.footprint, alignment: .bottom)
        .animation(reduceMotion ? nil : motion, value: pressed)
    }

    private func widthRatio(of cap: String, isSpace: Bool, hasLegend: Bool) -> CGFloat {
        if isSpace { return Keycap.spaceWidth }
        if cap == ModifierKey.globeGlyph { return Keycap.globeWidth }
        if hasLegend { return Keycap.modifierWidth }
        let labelled = CGFloat(cap.count) * Keycap.widthPerCharacter + Keycap.widthPadding
        return min(Keycap.maximumWidth, max(1, labelled))
    }

    @ViewBuilder
    private func keyLabel(_ cap: String, legend: String?, unit: CGFloat) -> some View {
        let glyph = KeyCapChip.Label(text: cap, prefix: binding.recorderPrefix)
        if let legend {
            let symbol = glyph.font(.system(size: unit * Keycap.symbolSize))
            let title = Text(verbatim: legend).font(.system(size: unit * Keycap.legendSize))
            Group {
                if cap == ModifierKey.globeGlyph {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        symbol
                        Spacer(minLength: 0)
                        title
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        symbol
                        Spacer(minLength: 0)
                        title
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, unit * Keycap.legendVerticalInset)
                }
            }
            .padding(.horizontal, unit * Keycap.legendHorizontalInset)
            .padding(.bottom, unit * Keycap.legendVerticalInset)
        } else {
            glyph.font(.system(size: unit * (cap.count > 2 ? Keycap.nameSize : Keycap.glyphSize)))
                .lineLimit(1)
                .minimumScaleFactor(Keycap.glyphMinimumScale)
                .offset(y: cap == Self.spaceGlyph ? -unit * Keycap.spaceGlyphRaise : 0)
                .padding(.horizontal, unit * Keycap.glyphInset)
        }
    }

    private func keyLegend(_ cap: String) -> String? {
        switch cap {
        case "⌘": "command"
        case "⌥": "option"
        case "⌃": "control"
        case "⇧": "shift"
        case ModifierKey.globeGlyph: "fn"
        default: nil
        }
    }

    private func isHeld(_ cap: String, at index: Int, count: Int) -> Bool {
        if binding.shortcut != nil {
            guard index < count - 1 else { return false }
        } else if index > 0 {
            return false
        }
        switch cap {
        case "⌘": return heldModifiers.contains(.command)
        case "⌥": return heldModifiers.contains(.option)
        case "⌃": return heldModifiers.contains(.control)
        case "⇧": return heldModifiers.contains(.shift)
        case HyperKeyPhysicalKey.hyperGlyph:
            guard let flags = KeyShortcut.displayedHyperChord() else { return false }
            return heldModifiers.isSuperset(
                of: flags.contains(.shift)
                    ? [.command, .option, .control, .shift] : [.command, .option, .control])
        default: return false
        }
    }
}

private struct ShortcutNotice: View {
    let notice: OnboardingShortcutSession.Notice
    let session: OnboardingShortcutSession
    let keys: Text

    var body: some View {
        switch notice {
        case .taken:
            VStack(spacing: Theme.Spacing.xs) {
                Label("\(keys) is already in use.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.Colors.warning)
                Text("Disable or change it where it’s assigned to use it in Tinycast.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .heldBySpotlight:
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Spotlight also uses \(keys).")
                        .font(.callout.weight(.semibold))
                    Text("Turn off Spotlight's shortcut and use it to open Tinycast.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Button("Replace Spotlight", action: session.replaceSpotlight)
                    .buttonStyle(.glass)
            }
        case .suggestion:
            Button("Use Suggested Shortcut", action: session.useSuggestion)
                .buttonStyle(.glass)
        case .spotlightOff:
            HStack(spacing: Theme.Spacing.sm) {
                Text("Spotlight's shortcut is off.")
                    .foregroundStyle(.secondary)
                Button("Undo", action: session.undoSpotlightReplacement)
                    .buttonStyle(.link)
                    .foregroundStyle(Theme.Colors.brand)
            }
            .font(.callout)
        }
    }
}
