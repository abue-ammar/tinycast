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

    // AX reports special keys as PUA scalars no text font renders; map them to visible glyphs.
    var displayCharacter: String {
        guard character.unicodeScalars.count == 1,
            let scalar = character.unicodeScalars.first
        else { return character }
        switch scalar.value {
        case 0xF700: return "↑"
        case 0xF701: return "↓"
        case 0xF702: return "←"
        case 0xF703: return "→"
        case 0xF729: return "↖"
        case 0xF72B: return "↘"
        case 0xF72C: return "⇞"
        case 0xF72D: return "⇟"
        default: return character
        }
    }

    // Glyphs in the order macOS menus use, so a row reads like the menu it came from.
    var keycaps: [String] {
        guard !character.isEmpty, hasCommand || hasShift || hasOption || hasControl else {
            return []
        }
        var caps: [String] = []
        if hasControl { caps.append("⌃") }
        if hasOption { caps.append("⌥") }
        if hasShift { caps.append("⇧") }
        if hasCommand { caps.append("⌘") }
        caps.append(displayCharacter.uppercased())
        return caps
    }

    var displayString: String? {
        let caps = keycaps
        return caps.isEmpty ? nil : caps.joined()
    }
}
