import AppKit
import Carbon.HIToolbox

/// A shortcut in Carbon's encoding, which is also the on-disk shape. See docs/features/hotkeys.md.
struct KeyShortcut: Hashable, Sendable {
    enum Modifier: String, CaseIterable, Codable, Sendable {
        case control, option, shift, command

        var glyph: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }

        var flag: NSEvent.ModifierFlags {
            switch self {
            case .control: .control
            case .option: .option
            case .shift: .shift
            case .command: .command
            }
        }

        var carbonMask: Int {
            switch self {
            case .control: controlKey
            case .option: optionKey
            case .shift: shiftKey
            case .command: cmdKey
            }
        }

        var deviceMasks: (left: UInt, right: UInt) {
            switch self {
            case .control: (0x0001, 0x2000)
            case .option: (0x0020, 0x0040)
            case .shift: (0x0002, 0x0004)
            case .command: (0x0008, 0x0010)
            }
        }
    }

    enum ModifierSide: String, CaseIterable, Codable, Sendable {
        case any, left, right
    }

    let carbonKeyCode: Int
    let carbonModifiers: Int
    let modifierSides: [Modifier: ModifierSide]
    let keyEquivalent: String?

    init(
        carbonKeyCode: Int, carbonModifiers: Int,
        modifierSides: [Modifier: ModifierSide] = [:], keyEquivalent: String? = nil
    ) {
        self.carbonKeyCode = carbonKeyCode
        // Mask to the supported modifiers, so device bits can't throw equality off.
        self.carbonModifiers = carbonModifiers & Self.allModifiers
        self.modifierSides = modifierSides.filter {
            $0.value != .any && carbonModifiers & $0.key.carbonMask != 0
        }
        self.keyEquivalent = keyEquivalent?.lowercased()
    }

    /// Captures from a key-down, or nil: one of ⌘⌥⌃🌐 is required, bar function keys.
    init?(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection([.command, .option, .control, .shift, .function])
        let hasCommandingModifier = !flags.isDisjoint(with: [.command, .option, .control, .function])
        guard hasCommandingModifier || Self.isFunctionKey(keyCode) else { return nil }
        self.init(carbonKeyCode: keyCode, carbonModifiers: Self.carbonModifiers(from: flags))
    }

    /// The chord ✦ stands for, nil without a Hyper key; a closure, so a toggle re-renders keycaps.
    @MainActor static var displayedHyperChord: () -> NSEvent.ModifierFlags? = { nil }

    /// One string per keycap in canonical order (🌐⌃⌥⇧⌘), with the key glyph last.
    @MainActor var keycaps: [String] {
        let caps =
            modifierSides.isEmpty
            ? Self.collapsedModifierSymbols(from: modifierFlags, hyperChord: Self.displayedHyperChord())
            : (modifierFlags.contains(.function) ? ["🌐︎"] : [])
                + modifiers.map { modifier in
                    switch modifierSide(for: modifier) {
                    case .any: modifier.glyph
                    case .left: "L" + modifier.glyph
                    case .right: "R" + modifier.glyph
                    }
                }
        return caps + [keyGlyph]
    }

    var modifierFlags: NSEvent.ModifierFlags { Self.modifierFlags(from: carbonModifiers) }
    var modifiers: [Modifier] { Modifier.allCases.filter { carbonModifiers & $0.carbonMask != 0 } }
    var requiresEventTap: Bool { !modifierSides.isEmpty || keyEquivalent != nil }

    func modifierSide(for modifier: Modifier) -> ModifierSide { modifierSides[modifier] ?? .any }

    func settingSide(_ side: ModifierSide, for modifier: Modifier) -> KeyShortcut {
        var sides = modifierSides
        sides[modifier] = side == .any ? nil : side
        return KeyShortcut(
            carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers,
            modifierSides: sides, keyEquivalent: keyEquivalent)
    }

    func usingPhysicalKey() -> KeyShortcut {
        KeyShortcut(
            carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers,
            modifierSides: modifierSides)
    }

    func usingKeyEquivalent(_ character: String) -> KeyShortcut {
        KeyShortcut(
            carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers,
            modifierSides: modifierSides, keyEquivalent: character)
    }

    func matches(keyCode: Int, modifierFlags flags: NSEvent.ModifierFlags, character: String?) -> Bool {
        guard Self.carbonModifiers(from: flags) == carbonModifiers else { return false }
        for modifier in modifiers {
            let masks = modifier.deviceMasks
            switch modifierSide(for: modifier) {
            case .any: break
            case .left:
                guard flags.rawValue & masks.left != 0, flags.rawValue & masks.right == 0 else {
                    return false
                }
            case .right:
                guard flags.rawValue & masks.right != 0, flags.rawValue & masks.left == 0 else {
                    return false
                }
            }
        }
        if let keyEquivalent { return character?.lowercased() == keyEquivalent }
        return keyCode == carbonKeyCode
    }

    func overlaps(
        with other: KeyShortcut, characterForKeyCode: (Int, Int) -> String?
    ) -> Bool {
        guard carbonModifiers == other.carbonModifiers else { return false }
        for modifier in modifiers {
            let side = modifierSide(for: modifier)
            let otherSide = other.modifierSide(for: modifier)
            if side != .any, otherSide != .any, side != otherSide { return false }
        }
        switch (keyEquivalent, other.keyEquivalent) {
        case (nil, nil): return carbonKeyCode == other.carbonKeyCode
        case (let lhs?, let rhs?): return lhs == rhs
        case (let character?, nil):
            return characterForKeyCode(other.carbonKeyCode, carbonModifiers)?.lowercased() == character
        case (nil, let character?):
            return characterForKeyCode(carbonKeyCode, carbonModifiers)?.lowercased() == character
        }
    }

    static func modifierFlags(from carbonModifiers: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & controlKey != 0 { flags.insert(.control) }
        if carbonModifiers & optionKey != 0 { flags.insert(.option) }
        if carbonModifiers & shiftKey != 0 { flags.insert(.shift) }
        if carbonModifiers & cmdKey != 0 { flags.insert(.command) }
        if carbonModifiers & kEventKeyModifierFnMask != 0 { flags.insert(.function) }
        return flags
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.function) { carbon |= kEventKeyModifierFnMask }
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
            carbonKeyCode: carbonKeyCode, carbonModifiers: Self.carbonModifiers(from: retargeted),
            modifierSides: modifierSides, keyEquivalent: keyEquivalent)
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

    /// Modifier symbols in fixed 🌐⌃⌥⇧⌘ order.
    static func modifierSymbols(from flags: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if flags.contains(.function) { symbols.append("🌐︎") }
        if flags.contains(.control) { symbols.append("⌃") }
        if flags.contains(.option) { symbols.append("⌥") }
        if flags.contains(.shift) { symbols.append("⇧") }
        if flags.contains(.command) { symbols.append("⌘") }
        return symbols
    }

    static func isFunctionKey(_ keyCode: Int) -> Bool {
        functionKeyNames[keyCode] != nil
    }

    private static let allModifiers = cmdKey | optionKey | controlKey | shiftKey | kEventKeyModifierFnMask

    // MARK: - Key glyph

    /// A fixed table for keys with no character, else translated through the current layout.
    @MainActor var keyGlyph: String {
        if let keyEquivalent { return keyEquivalent.uppercased() }
        if let special = Self.specialKeyGlyphs[carbonKeyCode] { return special }
        if let name = Self.functionKeyNames[carbonKeyCode] { return name }
        return ASCIIKeyboardLayout.character(for: carbonKeyCode)?.uppercased() ?? "?"
    }

    @MainActor var supportsKeyEquivalent: Bool {
        guard Self.specialKeyGlyphs[carbonKeyCode] == nil,
            Self.functionKeyNames[carbonKeyCode] == nil,
            let character = ASCIIKeyboardLayout.character(for: carbonKeyCode)
        else { return false }
        return character.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value != 0x7F }
    }

    @MainActor var equivalentCharacter: String? {
        if let keyEquivalent { return keyEquivalent }
        return Self.character(for: carbonKeyCode, carbonModifiers: carbonModifiers)?.lowercased()
    }

    @MainActor static func character(for keyCode: Int, carbonModifiers: Int) -> String? {
        ASCIIKeyboardLayout.character(
            for: keyCode, modifiers: carbonModifiers & cmdKey != 0 ? UInt32(cmdKey >> 8) : 0)
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
        case carbonKeyCode, carbonModifiers, modifierSides, keyEquivalent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            carbonKeyCode: try container.decode(Int.self, forKey: .carbonKeyCode),
            carbonModifiers: try container.decode(Int.self, forKey: .carbonModifiers),
            modifierSides: try container.decodeIfPresent(
                [Modifier: ModifierSide].self, forKey: .modifierSides) ?? [:],
            keyEquivalent: try container.decodeIfPresent(String.self, forKey: .keyEquivalent)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(carbonKeyCode, forKey: .carbonKeyCode)
        try container.encode(carbonModifiers, forKey: .carbonModifiers)
        if !modifierSides.isEmpty { try container.encode(modifierSides, forKey: .modifierSides) }
        try container.encodeIfPresent(keyEquivalent, forKey: .keyEquivalent)
    }
}
