import SwiftUI

/// What a key press means to a control that drops a list. One place decides, so a character rule
/// can never shadow ⌫ the way a stack of separate `onKeyPress` modifiers let it.
enum ExtensionListKey: Equatable {
    case openList
    case moveUp
    case moveDown
    case commit
    case dismiss
    case append(String)
    case deleteBackward
    /// ←/→ on a closed single-select control, which steps its value without opening anything.
    case stepValue(Int)
    case ignored

    init(press: KeyPress, listOpen: Bool) {
        self = ExtensionListKey.resolve(
            key: press.key, characters: press.characters, modifiers: press.modifiers,
            listOpen: listOpen)
    }

    /// Split out so a harness can drive it: `KeyPress` cannot be constructed outside SwiftUI.
    static func resolve(
        key: KeyEquivalent, characters: String, modifiers: EventModifiers, listOpen: Bool
    ) -> ExtensionListKey {
        // A chord belongs to whoever bound it — ⌘K, an action's shortcut — never to this list.
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }

        switch key {
        case .upArrow: return listOpen ? .moveUp : .ignored
        case .downArrow: return listOpen ? .moveDown : .openList
        case .return: return listOpen ? .commit : .openList
        case .escape: return listOpen ? .dismiss : .ignored
        case .leftArrow: return listOpen ? .ignored : .stepValue(-1)
        case .rightArrow: return listOpen ? .ignored : .stepValue(1)
        case .space: return listOpen ? .append(" ") : .openList
        case .tab: return .ignored
        default: break
        }

        // Measured, not assumed: the ⌫ key arrives carrying U+007F, while SwiftUI's `.delete`
        // is U+0008, so matching the named constant alone never fired and nothing was deleted.
        if isDeletion(key: key, characters: characters) {
            return listOpen ? .deleteBackward : .ignored
        }

        guard listOpen, !characters.isEmpty, characters.allSatisfy(isTypable) else {
            return .ignored
        }
        return .append(characters)
    }

    /// Only what a search field would show: a control key's own character must not become text.
    private static func isTypable(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first
        else { return true }
        return !CharacterSet.controlCharacters.contains(scalar)
            && !CharacterSet.illegalCharacters.contains(scalar)
    }

    /// Both spellings of every delete key: the named equivalents and the scalars they carry.
    private static func isDeletion(key: KeyEquivalent, characters: String) -> Bool {
        if key == .delete || key == .deleteForward { return true }
        let deletions: Set<Unicode.Scalar> = ["\u{8}", "\u{7F}"]
        if deletions.contains(key.character.unicodeScalars.first ?? " ") { return true }
        guard characters.unicodeScalars.count == 1, let scalar = characters.unicodeScalars.first
        else { return false }
        return deletions.contains(scalar)
    }
}
