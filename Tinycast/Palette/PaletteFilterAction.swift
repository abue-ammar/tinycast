import Foundation

/// Which type filter ⌘P opens. The header shows at most one, so this says which — and a running
/// command's own dropdown answers first, so Tinycast's clipboard filter can never open over it.
enum PaletteFilterAction: Equatable {
    /// A running command's `searchBarAccessory` dropdown.
    case extensionAccessory
    case clipboardFilter
    case fileSearchFilter
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
        default: return .ignored
        }
    }
}
