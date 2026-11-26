import SwiftUI

struct OnboardingKeys: View {
    private typealias Keycap = Theme.Onboarding.Keycap

    let session: OnboardingShortcutSession

    var body: some View {
        let layout = Layout(
            binding: session.binding, held: session.heldCaps, confirmed: session.isConfirmed)
        ViewThatFits(in: .horizontal) {
            row(layout, scale: 1)
            row(layout, scale: Keycap.compactScale)
            row(layout, scale: Keycap.smallestScale)
        }
        .opacity(session.assignedBinding == nil && !layout.isLive ? Keycap.unboundOpacity : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Launcher shortcut")
        .accessibilityValue(Text(verbatim: layout.caps.joined(separator: " ")))
    }

    private func row(_ layout: Layout, scale: CGFloat) -> some View {
        let unit = Keycap.size * scale
        let space = String(localized: "Space")
        return HStack(spacing: unit * Keycap.gap) {
            ForEach(layout.caps.indices, id: \.self) { index in
                if layout.joinsKey, index == layout.caps.count - 1 {
                    Image(systemName: "plus")
                        .font(.system(size: unit * Keycap.plusSize, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                let cap = layout.caps[index]
                Key(
                    cap: cap, prefix: layout.prefix, isSpace: cap == space, unit: unit,
                    pressed: layout.pressed[index])
            }
        }
        .fixedSize()
    }

    /// Held modifiers replace the binding as soon as they stop being a part of it.
    private struct Layout {
        let caps: [String]
        let prefix: String?
        let pressed: [Bool]
        let joinsKey: Bool
        let isLive: Bool

        @MainActor
        init(binding: HotKeyBinding, held: [String], confirmed: Bool) {
            let bindingCaps = binding.recorderKeycaps
            let modifierCount = binding.shortcut == nil ? bindingCaps.count : bindingCaps.count - 1
            let modifierCaps = bindingCaps.prefix(modifierCount)
            guard held.isEmpty || held.allSatisfy(modifierCaps.contains) else {
                caps = held
                prefix = nil
                pressed = held.map { _ in true }
                joinsKey = false
                isLive = true
                return
            }
            caps = bindingCaps
            prefix = binding.recorderPrefix
            pressed = bindingCaps.indices.map { index in
                confirmed || (index < modifierCount && held.contains(bindingCaps[index]))
            }
            joinsKey = binding.shortcut != nil
            isLive = !held.isEmpty
        }
    }

    private struct Key: View {
        let cap: String
        let prefix: String?
        let isSpace: Bool
        let unit: CGFloat
        let pressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let legend = Self.legend(for: cap)
            let width = unit * widthRatio(hasLegend: legend != nil)
            let shape = RoundedRectangle(cornerRadius: unit * Keycap.cornerRadius, style: .continuous)
            let contact = pressed ? Keycap.pressedContactShadow : Keycap.contactShadow
            let ambient = pressed ? Keycap.pressedAmbientShadow : Keycap.ambientShadow
            let motion = pressed ? Keycap.press : Keycap.release
            label(legend: legend)
                .foregroundStyle(pressed ? Keycap.pressedInk : Keycap.ink)
                .frame(minWidth: width)
                .frame(height: unit)
                .background {
                    ZStack {
                        shape.fill(pressed ? Keycap.pressedFace : Keycap.face)
                        if pressed { shape.fill(Keycap.pressedTint) }
                        shape.fill(Keycap.sheen)
                        shape.fill(
                            RadialGradient(
                                colors: [Keycap.glow, .clear], center: .bottom, startRadius: 0,
                                endRadius: max(width, unit) * Keycap.glowReach))
                    }
                }
                .overlay {
                    shape.strokeBorder(Keycap.rim, lineWidth: Theme.Size.hairline)
                        .opacity(pressed ? Keycap.pressedRimOpacity : 1)
                }
                .background {
                    shape.inset(by: -Keycap.edgeWidth)
                        .fill(Keycap.edge)
                        .shadow(color: Keycap.contactShadowColor, radius: contact.radius, y: contact.offset)
                        .shadow(color: Keycap.ambientShadowColor, radius: ambient.radius, y: ambient.offset)
                }
                .offset(y: pressed ? Keycap.pressDepth : 0)
                .animation(reduceMotion ? nil : motion, value: pressed)
        }

        private func widthRatio(hasLegend: Bool) -> CGFloat {
            if isSpace { return Keycap.spaceWidth }
            return hasLegend ? Keycap.labelledWidth : 1
        }

        @ViewBuilder
        private func label(legend: String?) -> some View {
            let glyph = KeyCapChip.Label(text: cap, prefix: prefix)
            if let legend {
                VStack(alignment: .leading, spacing: 0) {
                    glyph.font(.system(size: unit * Keycap.symbolSize))
                    Spacer(minLength: 0)
                    Text(verbatim: legend).font(.system(size: unit * Keycap.legendSize))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, unit * Keycap.horizontalInset)
                .padding(.vertical, unit * Keycap.verticalInset)
            } else {
                glyph.font(.system(size: unit * (cap.count > 2 ? Keycap.nameSize : Keycap.glyphSize)))
                    .lineLimit(1)
                    .minimumScaleFactor(Keycap.glyphMinimumScale)
                    .padding(.horizontal, unit * Keycap.horizontalInset)
            }
        }

        private static func legend(for cap: String) -> String? {
            switch cap {
            case "⌘": "command"
            case "⌥": "option"
            case "⌃": "control"
            case "⇧": "shift"
            case ModifierKey.globeGlyph: "fn"
            default: nil
            }
        }
    }
}
