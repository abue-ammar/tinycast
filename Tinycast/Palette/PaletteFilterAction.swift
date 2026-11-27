import Foundation

/// Which header menu ⌘P opens.
enum PaletteFilterAction: Equatable {
    case clipboardFilter
    case fileSearchFilter
    case emojiCategory
    case dictionaryScope
    case aiModel
    /// No filter on the header, so the key stays with the search field.
    case ignored

    static func resolve(collapsed: Bool, mode: PaletteMode) -> Self {
        // The compact bar draws no header controls, so neither filter has a button to hang off.
        guard !collapsed else { return .ignored }
        switch mode {
        case .clipboard: return .clipboardFilter
        case .fileSearch: return .fileSearchFilter
        case .emoji: return .emojiCategory
        case .dictionary: return .dictionaryScope
        case .ai: return .aiModel
        default: return .ignored
        }
    }
}
