import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ASCIIKeyboardLayout {
    /// No modifiers by default: the key's base character, which is what a shortcut glyph shows.
    @MainActor static func character(for keyCode: Int, modifiers: UInt32 = 0) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(
                source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        let keyLayout = unsafeBitCast(
            CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let error = UCKeyTranslate(
            keyLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            modifiers,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    /// A layout owns its Command table: "Dvorak – QWERTY ⌘" only restores ⌘K to QWERTY through it.
    @MainActor static func character(for event: NSEvent) -> String? {
        character(
            for: Int(event.keyCode),
            modifiers: event.modifierFlags.contains(.command) ? UInt32(cmdKey >> 8) : 0)
    }

    /// SwiftUI exposes the input-source character; recover the logical ASCII key from AppKit.
    @MainActor static func keyEquivalent(fallingBackTo key: KeyEquivalent) -> KeyEquivalent {
        guard let event = NSApp.currentEvent,
            !event.modifierFlags.isDisjoint(with: [.command, .control]),
            let character = character(for: event)?.lowercased().first,
            character.unicodeScalars.allSatisfy(\.isASCII)
        else { return lowercased(key) }
        return KeyEquivalent(character)
    }

    /// Shift uppercases SwiftUI's key, but every chord spells its letter in lower case.
    private static func lowercased(_ key: KeyEquivalent) -> KeyEquivalent {
        key.character.lowercased().first.map { KeyEquivalent($0) } ?? key
    }

    @MainActor static func matches(_ key: KeyEquivalent, character: Character) -> Bool {
        keyEquivalent(fallingBackTo: key) == KeyEquivalent(character)
    }
}
