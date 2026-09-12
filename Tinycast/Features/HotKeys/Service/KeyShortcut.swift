import AppKit
import Carbon.HIToolbox

/// A shortcut in Carbon's encoding, which is also the on-disk shape. See docs/features/hotkeys.md.
struct KeyShortcut: Hashable, Sendable {
    let carbonKeyCode: Int
    let carbonModifiers: Int

    init(carbonKeyCode: Int, carbonModifiers: Int) {
        self.carbonKeyCode = carbonKeyCode
        // Mask to the four real modifiers, so device bits can't throw equality off.
        self.carbonModifiers = carbonModifiers & Self.allModifiers
    }

    /// Captures from a key-down, or nil: one of ⌘⌥⌃ is required, bar function keys.
    init?(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection([.command, .option, .control, .shift])
        let hasCommandingModifier = !flags.isDisjoint(with: [.command, .option, .control])
        guard hasCommandingModifier || Self.isFunctionKey(keyCode) else { return nil }
        self.init(carbonKeyCode: keyCode, carbonModifiers: Self.carbonModifiers(from: flags))
    }

    /// The chord ✦ stands for, nil without a Hyper key; a closure, so a toggle re-renders keycaps.
    @MainActor static var displayedHyperChord: () -> NSEvent.ModifierFlags? = { nil }

    /// One string per keycap in canonical order (⌃⌥⇧⌘), with the key glyph last.
    @MainActor var keycaps: [String] {
        Self.collapsedModifierSymbols(from: modifierFlags, hyperChord: Self.displayedHyperChord())
            + [keyGlyph]
    }

    var modifierFlags: NSEvent.ModifierFlags { Self.modifierFlags(from: carbonModifiers) }

    static func modifierFlags(from carbonModifiers: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & controlKey != 0 { flags.insert(.control) }
        if carbonModifiers & optionKey != 0 { flags.insert(.option) }
        if carbonModifiers & shiftKey != 0 { flags.insert(.shift) }
        if carbonModifiers & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        return carbon
    }

    // MARK: - The Hyper chord

    /// ⌃⌥⌘, plus ⇧ when Include Shift is on — the one place the chord is spelled out.
    static func hyperChord(includesShift: Bool) -> NSEvent.ModifierFlags {
        includesShift ? [.control, .option, .shift, .command] : [.control, .option, .command]
    }

    /// Re-points a chord recorded against the other Hyper set. docs/features/hotkeys.md
    func retargetingHyper(includesShift: Bool) -> KeyShortcut {
        let stale = Self.hyperChord(includesShift: !includesShift)
        guard modifierFlags.isSuperset(of: stale) else { return self }
        let retargeted =
            modifierFlags.subtracting(stale).union(Self.hyperChord(includesShift: includesShift))
        return KeyShortcut(
            carbonKeyCode: carbonKeyCode, carbonModifiers: Self.carbonModifiers(from: retargeted))
    }

    /// `modifierSymbols` with the Hyper chord collapsed to "✦", when one is configured at all.
    static func collapsedModifierSymbols(
        from flags: NSEvent.ModifierFlags, hyperChord: NSEvent.ModifierFlags?
    ) -> [String] {
        guard let hyperChord, flags.isSuperset(of: hyperChord) else {
            return modifierSymbols(from: flags)
        }
        return [HyperKeyPhysicalKey.hyperGlyph] + modifierSymbols(from: flags.subtracting(hyperChord))
    }

    /// Modifier symbols in the fixed ⌃⌥⇧⌘ order every macOS surface uses.
    static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    static func isFunctionKey(_ keyCode: Int) -> Bool {
        functionKeyNames[keyCode] != nil
    }

    private static let allModifiers = cmdKey | optionKey | controlKey | shiftKey

    // MARK: - Key glyph

    /// A fixed table for keys with no character, else translated through the current layout.
    @MainActor private var keyGlyph: String {
        if let special = Self.specialKeyGlyphs[carbonKeyCode] { return special }
        if let name = Self.functionKeyNames[carbonKeyCode] { return name }
        return ASCIIKeyboardLayout.character(for: carbonKeyCode)?.uppercased() ?? "?"
    }

    private static let specialKeyGlyphs: [Int: String] = [
        kVK_Return: "↵", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "Space",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "?⃝"
    ]

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20"
    ]

}

// Decoding routes through the masking initializer. See docs/features/hotkeys.md#persistence.
extension KeyShortcut: Codable {
    private enum CodingKeys: String, CodingKey {
        case carbonKeyCode, carbonModifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            carbonKeyCode: try container.decode(Int.self, forKey: .carbonKeyCode),
            carbonModifiers: try container.decode(Int.self, forKey: .carbonModifiers)
        )
    }
}
