import Foundation

struct MenuSearchShortcut: Hashable, Sendable {
    let character: String
    let hasCommand: Bool
    let hasShift: Bool
    let hasOption: Bool
    let hasControl: Bool

    // AX bits, verified live: 0 Shift, 1 Option, 2 Control, 3 clears the otherwise implied ⌘.
    static func commandEquivalent(character: String, modifiers: Int) -> Self? {
        guard !character.isEmpty, modifiers & ~0b1111 == 0 else { return nil }
        return Self(
            character: character,
            hasCommand: modifiers & 0b1000 == 0,
            hasShift: modifiers & 0b001 != 0,
            hasOption: modifiers & 0b010 != 0,
            hasControl: modifiers & 0b100 != 0)
    }

    // AX reports a non-typing key as a control or PUA scalar no text font draws; name it instead.
    var displayCharacter: String {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first
        else { return character.uppercased() }
        if let glyph = Self.glyphs[scalar.value] { return glyph }
        guard Self.functionKeys.contains(scalar.value) else { return character.uppercased() }
        return "F\(scalar.value - Self.functionKeys.lowerBound + 1)"
    }

    // Glyphs in the order macOS menus use, so a row reads like the menu it came from.
    var keycaps: [String] {
        guard !character.isEmpty else { return [] }
        var caps: [String] = []
        if hasControl { caps.append("⌃") }
        if hasOption { caps.append("⌥") }
        if hasShift { caps.append("⇧") }
        if hasCommand { caps.append("⌘") }
        caps.append(displayCharacter)
        return caps
    }

    var displayString: String? {
        let caps = keycaps
        return caps.isEmpty ? nil : caps.joined()
    }

    private static let functionKeys: ClosedRange<UInt32> = 0xF704...0xF726

    private static let glyphs: [UInt32: String] = [
        0x03: "⌤", 0x08: "⌫", 0x09: "⇥", 0x0D: "↩", 0x19: "⇤", 0x1B: "⎋", 0x20: "␣",
        0x7F: "⌫", 0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→", 0xF728: "⌦",
        0xF729: "↖", 0xF72B: "↘", 0xF72C: "⇞", 0xF72D: "⇟", 0xF739: "⌧", 0xF746: "?"
    ]
}
