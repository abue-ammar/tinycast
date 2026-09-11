import Foundation

struct MenuSearchShortcut: Hashable, Sendable {
    let character: String
    let hasCommand: Bool
    let hasShift: Bool
    let hasOption: Bool
    let hasControl: Bool

    // AX bits, verified live: 0 Shift, 1 Option, 2 Control, ⌘ implied; higher bits unrenderable.
    static func commandEquivalent(character: String, modifiers: Int) -> Self? {
        guard !character.isEmpty, modifiers & ~0b111 == 0 else { return nil }
        return Self(
            character: character, hasCommand: true,
            hasShift: modifiers & 0b001 != 0,
            hasOption: modifiers & 0b010 != 0,
            hasControl: modifiers & 0b100 != 0)
    }

    // Glyphs in the order macOS menus use, so a row reads like the menu it came from.
    var displayString: String? {
        guard !character.isEmpty, hasCommand || hasShift || hasOption || hasControl else {
            return nil
        }
        var glyphs = ""
        if hasControl { glyphs += "⌃" }
        if hasOption { glyphs += "⌥" }
        if hasShift { glyphs += "⇧" }
        if hasCommand { glyphs += "⌘" }
        return glyphs + character.uppercased()
    }
}
