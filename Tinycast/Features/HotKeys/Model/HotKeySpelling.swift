import Carbon.HIToolbox
import Foundation

/// A binding as a person types it into settings.json. See docs/features/settings-file.md.
struct HotKeySpelling: Sendable {
    /// The Hyper chord in Carbon bits while a Hyper key is set, so it spells as `hyper` again.
    let hyperModifiers: Int?
    private let characterByCode: [Int: String]
    private let codeByCharacter: [String: Int]

    /// `characters` is each key's base character on this Mac, the one its keycap shows.
    init(characters: [Int: String], hyperModifiers: Int?) {
        var characterByCode: [Int: String] = [:]
        var codeByCharacter: [String: Int] = [:]
        // Ascending, so a character two keys type is spelled by the lower one both ways.
        for (code, character) in characters.sorted(by: { $0.key < $1.key }) {
            let name = character.lowercased()
            guard Self.namedKeys[code] == nil, Self.isSpellable(name), codeByCharacter[name] == nil
            else { continue }
            characterByCode[code] = name
            codeByCharacter[name] = code
        }
        self.characterByCode = characterByCode
        self.codeByCharacter = codeByCharacter
        self.hyperModifiers = hyperModifiers
    }

    func text(for binding: HotKeyBinding) -> String {
        switch binding {
        case .combo(let shortcut): text(for: shortcut)
        case .doubleTap(let modifier): "double-tap " + Self.name(of: modifier)
        case .modifier(let key): Self.name(of: key)
        case .doubleModifier(let key): "double-tap " + Self.name(of: key)
        case .globe: "globe"
        case .doubleGlobe: "double-tap globe"
        }
    }

    /// Nil for anything the recorder would refuse, so the file can't bind what the app can't.
    func binding(from text: String) -> HotKeyBinding? {
        let spelled = text.trimmingCharacters(in: .whitespaces).lowercased()
        if spelled == "globe" { return .globe }
        if let key = Self.modifierKey(named: spelled) { return key.singleBinding }
        if spelled.hasPrefix(Self.doubleTapPrefix) {
            let modifier = String(spelled.dropFirst(Self.doubleTapPrefix.count))
            if modifier == "globe" { return .doubleGlobe }
            if let key = Self.modifierKey(named: modifier) { return key.doubleBinding }
            return Self.doubleTapModifier(named: modifier).map(HotKeyBinding.doubleTap)
        }
        return shortcut(from: spelled).map(HotKeyBinding.combo)
    }

    // MARK: - Combos

    private func text(for shortcut: KeyShortcut) -> String {
        var modifiers = shortcut.carbonModifiers
        var parts: [String] = []
        if let hyperModifiers, shortcut.modifierSides.isEmpty,
            modifiers & hyperModifiers == hyperModifiers
        {
            parts.append(Self.hyperName)
            modifiers &= ~hyperModifiers
        }
        for (mask, name) in Self.writtenModifiers where modifiers & mask != 0 {
            let modifier = KeyShortcut.Modifier.allCases.first { $0.carbonMask == mask }
            let side = modifier.map { shortcut.modifierSide(for: $0) } ?? .any
            parts.append(side == .any ? name : side.rawValue + "-" + name)
        }
        parts.append(
            shortcut.keyEquivalent.map {
                Self.rawKeyPrefix + String(shortcut.carbonKeyCode) + Self.characterSeparator + $0
            }
                ?? keyName(for: shortcut.carbonKeyCode))
        return parts.joined(separator: "+")
    }

    private func shortcut(from spelled: String) -> KeyShortcut? {
        var tokens = spelled.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // "cmd++" names the plus key itself, which the split leaves as two empty tokens.
        if tokens.count > 2, tokens.suffix(2).allSatisfy(\.isEmpty) {
            tokens.removeLast(2)
            tokens.append("+")
        }
        if tokens.count > 2, tokens.last == "",
            tokens[tokens.count - 2].hasSuffix(Self.characterSeparator)
        {
            let characterKey = tokens[tokens.count - 2] + "+"
            tokens.removeLast(2)
            tokens.append(characterKey)
        }
        guard let keyToken = tokens.popLast() else { return nil }
        let character: String?
        let physicalKey: String
        if let separator = keyToken.range(of: Self.characterSeparator) {
            character = String(keyToken[separator.upperBound...])
            physicalKey = String(keyToken[..<separator.lowerBound])
            guard let character, Self.isSpellable(character) else { return nil }
        } else {
            character = nil
            physicalKey = keyToken
        }
        guard let keyCode = keyCode(named: physicalKey) else { return nil }
        var modifiers = 0
        var sides: [KeyShortcut.Modifier: KeyShortcut.ModifierSide] = [:]
        for token in tokens {
            if token == Self.hyperName, let hyperModifiers {
                modifiers |= hyperModifiers
            } else {
                let side: KeyShortcut.ModifierSide
                let name: String
                if token.hasPrefix("left-") {
                    side = .left
                    name = String(token.dropFirst(5))
                } else if token.hasPrefix("right-") {
                    side = .right
                    name = String(token.dropFirst(6))
                } else {
                    side = .any
                    name = token
                }
                guard let mask = Self.modifierMasks[name] else { return nil }
                if side != .any {
                    guard let modifier = KeyShortcut.Modifier.allCases.first(where: { $0.carbonMask == mask })
                    else { return nil }
                    sides[modifier] = side
                }
                modifiers |= mask
            }
        }
        let commanding = modifiers & (cmdKey | optionKey | controlKey | kEventKeyModifierFnMask)
        guard commanding != 0 || KeyShortcut.isFunctionKey(keyCode) else { return nil }
        return KeyShortcut(
            carbonKeyCode: keyCode, carbonModifiers: modifiers, modifierSides: sides,
            keyEquivalent: character)
    }

    private func keyName(for keyCode: Int) -> String {
        Self.namedKeys[keyCode] ?? characterByCode[keyCode] ?? Self.rawKeyPrefix + String(keyCode)
    }

    private func keyCode(named name: String) -> Int? {
        if let code = Self.codeByName[name] ?? codeByCharacter[name] { return code }
        guard name.hasPrefix(Self.rawKeyPrefix),
            let code = Int(name.dropFirst(Self.rawKeyPrefix.count)), Self.keyCodes.contains(code)
        else { return nil }
        return code
    }

    // MARK: - Vocabulary

    private static let hyperName = "hyper"
    private static let doubleTapPrefix = "double-tap "
    private static let rawKeyPrefix = "key-"
    private static let characterSeparator = ":character:"
    private static let keyCodes = 0..<128

    /// The app's 🌐⌃⌥⇧⌘ order, so a spelled chord reads like its keycaps.
    private static let writtenModifiers: [(mask: Int, name: String)] = [
        (kEventKeyModifierFnMask, "fn"), (controlKey, "ctrl"), (optionKey, "option"),
        (shiftKey, "shift"), (cmdKey, "cmd")
    ]

    private static let modifierMasks: [String: Int] = [
        "fn": kEventKeyModifierFnMask,
        "ctrl": controlKey, "control": controlKey,
        "option": optionKey, "opt": optionKey, "alt": optionKey,
        "shift": shiftKey,
        "cmd": cmdKey, "command": cmdKey
    ]

    /// Keys whose character is invisible, or shared with a key the file must tell apart.
    private static let namedKeys: [Int: String] = [
        kVK_Space: "space", kVK_Return: "return", kVK_ANSI_KeypadEnter: "enter", kVK_Tab: "tab",
        kVK_Delete: "delete", kVK_ForwardDelete: "forward-delete", kVK_Escape: "escape",
        kVK_LeftArrow: "left", kVK_RightArrow: "right", kVK_UpArrow: "up", kVK_DownArrow: "down",
        kVK_Home: "home", kVK_End: "end", kVK_PageUp: "page-up", kVK_PageDown: "page-down",
        kVK_Help: "help",
        kVK_F1: "f1", kVK_F2: "f2", kVK_F3: "f3", kVK_F4: "f4", kVK_F5: "f5", kVK_F6: "f6",
        kVK_F7: "f7", kVK_F8: "f8", kVK_F9: "f9", kVK_F10: "f10", kVK_F11: "f11", kVK_F12: "f12",
        kVK_F13: "f13", kVK_F14: "f14", kVK_F15: "f15", kVK_F16: "f16", kVK_F17: "f17",
        kVK_F18: "f18", kVK_F19: "f19", kVK_F20: "f20",
        kVK_ANSI_Keypad0: "keypad-0", kVK_ANSI_Keypad1: "keypad-1", kVK_ANSI_Keypad2: "keypad-2",
        kVK_ANSI_Keypad3: "keypad-3", kVK_ANSI_Keypad4: "keypad-4", kVK_ANSI_Keypad5: "keypad-5",
        kVK_ANSI_Keypad6: "keypad-6", kVK_ANSI_Keypad7: "keypad-7", kVK_ANSI_Keypad8: "keypad-8",
        kVK_ANSI_Keypad9: "keypad-9", kVK_ANSI_KeypadDecimal: "keypad-decimal",
        kVK_ANSI_KeypadPlus: "keypad-plus", kVK_ANSI_KeypadMinus: "keypad-minus",
        kVK_ANSI_KeypadMultiply: "keypad-multiply", kVK_ANSI_KeypadDivide: "keypad-divide",
        kVK_ANSI_KeypadEquals: "keypad-equals", kVK_ANSI_KeypadClear: "keypad-clear"
    ]

    private static let codeByName = Dictionary(
        uniqueKeysWithValues: namedKeys.map { ($0.value, $0.key) })

    private static func isSpellable(_ name: String) -> Bool {
        !name.isEmpty
            && name.unicodeScalars.allSatisfy {
                $0.value > 0x20 && $0.value != 0x7F && !$0.properties.isWhitespace
            }
    }

    private static func name(of modifier: DoubleTapModifier) -> String {
        switch modifier {
        case .control: "ctrl"
        case .option: "option"
        case .shift: "shift"
        case .command: "cmd"
        }
    }

    private static func name(of key: ModifierKey) -> String {
        guard let side = key.side, let modifier = key.modifier else { return "globe" }
        return side.lowercased() + " " + name(of: modifier)
    }

    private static func modifierKey(named name: String) -> ModifierKey? {
        let parts = name.split(separator: " ")
        guard parts.count == 2, let modifier = doubleTapModifier(named: String(parts[1])) else {
            return nil
        }
        return ModifierKey.allCases.first {
            $0.side?.lowercased() == String(parts[0]) && $0.modifier == modifier
        }
    }

    private static func doubleTapModifier(named name: String) -> DoubleTapModifier? {
        switch modifierMasks[name] {
        case controlKey: .control
        case optionKey: .option
        case shiftKey: .shift
        case cmdKey: .command
        default: nil
        }
    }
}
