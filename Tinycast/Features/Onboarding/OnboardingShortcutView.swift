import Carbon.HIToolbox
import SwiftUI

struct OnboardingShortcutView: View {
    let confirmed: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @State private var heldModifiers: SwiftUI.EventModifiers = []
    @State private var hoveringShortcut = false
    @State private var shortcutIsInUse = false

    private static let suggestedBinding = HotKeyBinding.combo(
        KeyShortcut(carbonKeyCode: kVK_Space, carbonModifiers: cmdKey))

    private var assignedBinding: HotKeyBinding? { hotKeys.binding(for: .togglePalette) }
    private var binding: HotKeyBinding { assignedBinding ?? Self.suggestedBinding }
    private var isRecording: Bool { hotKeys.recordingAction == .togglePalette }

    var body: some View {
        @Bindable var settings = settings
        let showsSuggestion = assignedBinding == nil && !isRecording
        VStack(spacing: Theme.Spacing.xxxl) {
            OnboardingSetupPages.Header(
                title: assignedBinding != nil && !shortcutIsInUse
                    ? "Try your shortcut" : "Set Up Your Launcher"
            ) {
                if assignedBinding != nil && !shortcutIsInUse {
                    Text("Press this shortcut to open Tinycast.")
                        .foregroundStyle(.secondary)
                }
            }
            shortcutButton
            if shortcutIsInUse {
                let shortcut = Text(verbatim: binding.keycaps.joined(separator: " ")).bold()
                VStack(spacing: Theme.Spacing.xs) {
                    Label("\(shortcut) is already in use.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Disable or change it where it’s assigned to use it in Tinycast.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if showsSuggestion {
                Button("Use Suggested Shortcut") {
                    checkAvailability()
                    guard !shortcutIsInUse else { return }
                    hotKeys.setBinding(binding, for: .togglePalette)
                }
                .buttonStyle(.glass)
            }
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(confirmed)
                .padding(.top, shortcutIsInUse || showsSuggestion ? Theme.Spacing.md : 0)
        }
        .multilineTextAlignment(.center)
        .onModifierKeysChanged { _, held in heldModifiers = held }
        .onChange(of: appearsActive) { _, active in
            if active { checkAvailability() } else { heldModifiers = [] }
        }
        .onChange(of: assignedBinding, initial: true) {
            heldModifiers = []
            checkAvailability()
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
                hotKeys.recordingAction = .togglePalette
                hotKeys.capture.checksExternalConflicts = true
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                keys(scale: 1)
                keys(scale: 0.72)
                keys(scale: 0.52)
            }
            .padding(Theme.Onboarding.keyHoverInset)
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
        .padding(-Theme.Onboarding.keyHoverInset)
        .accessibilityLabel("Record Hotkey")
        .accessibilityValue(Text(verbatim: binding.keycaps.joined(separator: " ")))
        .background {
            if isRecording { ShortcutRecorderHitRegion(capture: hotKeys.capture) }
        }
        .anchorPreference(key: ShortcutRecorderAnchorKey.self, value: .bounds) {
            isRecording ? $0 : nil
        }
    }

    private func checkAvailability() {
        guard !confirmed else { return }
        shortcutIsInUse =
            hotKeys.conflictOwner(
                of: binding, excluding: .togglePalette, includingExternal: true) != nil
    }

    private func keys(scale: CGFloat) -> some View {
        let caps = binding.recorderKeycaps
        let space = String(localized: "Space")
        let unit = Theme.Onboarding.keySize * scale
        return HStack(spacing: unit * 0.17) {
            ForEach(caps.indices, id: \.self) { index in
                let cap = caps[index]
                key(
                    cap, isSpace: cap == space, scale: scale,
                    pressed: confirmed || isHeld(cap, at: index, count: caps.count))
            }
        }
        .fixedSize()
        .background {
            RoundedRectangle(cornerRadius: unit * 0.16)
                .fill(Theme.Onboarding.keyGlow)
                .padding(-unit * 0.06)
                .blur(radius: unit * 0.38)
                .allowsHitTesting(false)
        }
    }

    private func key(_ cap: String, isSpace: Bool, scale: CGFloat, pressed: Bool) -> some View {
        let unit = Theme.Onboarding.keySize * scale
        let legend = keyLegend(cap)
        let widthRatio: CGFloat =
            if isSpace { Theme.Onboarding.spaceKeyWidthRatio } else if cap == "🌐︎" {
                1.2
            } else if legend != nil { 1.55 } else {
                min(2.2, max(1, CGFloat(cap.count) * 0.4 + 0.6))
            }
        let width = unit * widthRatio
        let lift = unit * (pressed ? 0.04 : 0.10)
        let shape = RoundedRectangle(cornerRadius: unit * 0.105, style: .continuous)
        let pressure = pressed ? Animation.easeOut(duration: 0.055) : .spring(duration: 0.18, bounce: 0.15)
        return ZStack(alignment: .bottom) {
            shape.fill(Theme.Onboarding.keyBase)
                .frame(height: unit + lift)
                .shadow(color: .black.opacity(pressed ? 0.14 : 0.24), radius: unit * 0.13, y: unit * 0.055)

            keyLabel(isSpace ? "␣" : cap, legend: legend, unit: unit)
                .foregroundStyle(Theme.Onboarding.keyInk)
                .frame(width: width, height: unit)
                .background(Theme.Onboarding.keyFace, in: shape)
                .overlay { shape.strokeBorder(Theme.Onboarding.keyRim, lineWidth: unit * 0.012) }
                .offset(y: -lift)
        }
        .frame(width: width, height: unit * 1.1, alignment: .bottom)
        .animation(reduceMotion ? nil : pressure, value: pressed)
    }

    @ViewBuilder
    private func keyLabel(_ cap: String, legend: String?, unit: CGFloat) -> some View {
        let glyph = KeyCapChip.Label(text: cap, prefix: binding.recorderPrefix)
        if let legend {
            let symbol = glyph.font(.system(size: unit * 0.33))
            let title = Text(verbatim: legend).font(.system(size: unit * 0.21))
            Group {
                if cap == "🌐︎" {
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
                    .padding(.top, unit * 0.11)
                }
            }
            .padding(.horizontal, unit * 0.17)
            .padding(.bottom, unit * 0.11)
        } else {
            glyph.font(.system(size: unit * (cap.count > 2 ? 0.26 : 0.44)))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .offset(y: cap == "␣" ? -unit * 0.15 : 0)
                .padding(.horizontal, unit * 0.12)
        }
    }

    private func keyLegend(_ cap: String) -> String? {
        switch cap {
        case "⌘": "command"
        case "⌥": "option"
        case "⌃": "control"
        case "⇧": "shift"
        case "🌐︎": "fn"
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
