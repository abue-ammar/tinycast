import Foundation

/// Which header menu ⌘P opens; a running command's own dropdown always answers first.
enum PaletteFilterAction: Equatable {
    /// A running command's `searchBarAccessory` dropdown.
    case extensionAccessory
    case clipboardFilter
    case fileSearchFilter
    case emojiCategory
    case aiModel
    /// No filter on the header, so the key stays with the search field.
    case ignored

    static func resolve(
        collapsed: Bool, mode: PaletteMode, commandHasAccessory: Bool
    ) -> Self {
        // The compact bar draws no header controls, so neither filter has a button to hang off.
        guard !collapsed else { return .ignored }
        switch mode {
        case .extensionCommand: return commandHasAccessory ? .extensionAccessory : .ignored
        case .clipboard: return .clipboardFilter
        case .fileSearch: return .fileSearchFilter
        case .emoji: return .emojiCategory
        case .ai: return .aiModel
        default: return .ignored
        }
    }
}
