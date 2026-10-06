import SwiftUI

struct ShortcutKeyEditor: View {
    let shortcut: KeyShortcut
    let action: HotKeyAction

    @Environment(HotKeyManager.self) private var hotKeys
    private var capture: ShortcutCaptureSession { hotKeys.capture }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                if shortcut.modifierFlags.contains(.function) {
                    KeyCapChip(text: "🌐︎", scale: .hero)
                }
                ForEach(shortcut.modifiers, id: \.self) { modifier in
                    let side = shortcut.modifierSide(for: modifier)
                    let nextSide: KeyShortcut.ModifierSide =
                        switch side {
                        case .any: .left
                        case .left: .right
                        case .right: .any
                        }
                    cap(
                        text: modifierCap(modifier),
                        label: "Edit \(modifier.rawValue.capitalized) key side",
                        value: sideTitle(side),
                        help: "Click to cycle: Any Side → Left → Right → Any Side."
                    ) {
                        update(shortcut.settingSide(nextSide, for: modifier))
                    }
                }
                if shortcut.supportsKeyEquivalent,
                    let character = shortcut.keyEquivalent ?? shortcut.equivalentCharacter
                {
                    let physical = shortcut.keyEquivalent == nil
                    cap(
                        text: "\(shortcut.keyGlyph) · \(physical ? "Pos" : "Char")",
                        label: "Edit character key mode",
                        value: physical ? "Physical Key" : "Key Equivalent",
                        help: "Click to switch between physical key position and character across layouts."
                    ) {
                        update(
                            physical
                                ? shortcut.usingKeyEquivalent(character) : shortcut.usingPhysicalKey())
                    }
                } else {
                    KeyCapChip(text: shortcut.keyGlyph, scale: .hero)
                }
            }
            .frame(height: Theme.Size.heroKeyCap)

            HStack(spacing: Theme.Spacing.xs) {
                Text(capture.conflict?.owner ?? "Click keys to edit further")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(
                        capture.conflict == nil ? Theme.Colors.textSecondary : .orange
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                SymbolImage(name: "info.circle", size: Theme.Size.compactKeyCap, monochrome: true)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .help(
                        "Modifier keys cycle through Any Side, Left and Right. "
                            + "Character keys switch between physical key position and character across layouts."
                    )
            }
            .frame(height: Theme.Size.shortcutPopoverLine)
        }
    }

    private func cap(
        text: String, label: String, value: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            KeyCapChip(text: text, scale: .hero)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .help(help)
    }

    private func modifierCap(_ modifier: KeyShortcut.Modifier) -> String {
        switch shortcut.modifierSide(for: modifier) {
        case .any: modifier.glyph
        case .left: "L" + modifier.glyph
        case .right: "R" + modifier.glyph
        }
    }

    private func sideTitle(_ side: KeyShortcut.ModifierSide) -> String {
        switch side {
        case .any: "Any Side"
        case .left: "Left"
        case .right: "Right"
        }
    }

    private func update(_ shortcut: KeyShortcut) {
        capture.updateShortcut(shortcut, action: action, hotKeys: hotKeys)
    }
}
