import SwiftUI

enum ExtensionFormKey {
    static let enterKeys: Set<KeyEquivalent> = [.return, KeyEquivalent("\u{3}")]

    enum Action: Equatable {
        case activate, submit, consume, ignored
    }

    static func resolve(
        field: ExtensionFormField, key: KeyEquivalent, modifiers: EventModifiers,
        repeating: Bool = false, menuOpen: Bool = false, composing: Bool = false
    ) -> Action {
        guard !menuOpen, !composing, field.isFocusable else { return .ignored }
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        if enterKeys.contains(key) {
            if modifiers == .command { return repeating ? .consume : .submit }
            guard modifiers.isEmpty else { return .ignored }
            if field == .textArea { return .ignored }
            if field == .text || repeating { return .consume }
            return .activate
        }
        if key == .space, modifiers.isEmpty, field == .checkbox || field == .filePicker {
            return repeating ? .consume : .activate
        }
        return .ignored
    }
}
