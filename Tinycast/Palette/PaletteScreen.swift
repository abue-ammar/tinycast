import SwiftUI

/// Which arrow pair a move came from: ↑/↓ or ←/→.
enum PaletteAxis {
    case vertical
    case horizontal
}

/// One palette mode. `rows` is its single source of visible order, so selection indexes it.
@MainActor protocol PaletteScreen {
    associatedtype Row: Identifiable

    var rows: [Row] { get }
    var primaryActionTitle: String { get }

    /// False when the selection can't be acted on, which hides the footer pill and swallows ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool
    func actions(at selection: Int) -> PopoverMenuContent?
    func activate(at selection: Int)
    /// ⌘↵. False when the selection has no secondary action, leaving the key unhandled.
    func secondary(at selection: Int) -> Bool
    /// ⌥↵. False on every screen with nothing to paste, which is most of them.
    func pasteKeepingWindowOpen(at selection: Int) -> Bool
    /// The selection an arrow key lands on, or nil to leave the key to the palette's own default.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int?
    /// Controls the row wants beside the search field. `focus` is lent: the palette owns it either way.
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    @ViewBuilder func body(selection: Int, scroll: ScrollIntent) -> AnyView
}

extension PaletteScreen {
    func hasPrimaryAction(at selection: Int) -> Bool { true }
    func pasteKeepingWindowOpen(at selection: Int) -> Bool { false }
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? { nil }
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    { nil }
}

/// Controls beside the search field, in terms the palette can act on without knowing what they are.
struct PaletteHeaderAccessory {
    /// How much room the strip needs, so the search field can give it up.
    let width: CGFloat
    /// Focusable fields in visual order; Tab walks these before it leaves the header.
    let fieldNames: [String]
    /// The first field that still has to be filled before ↵ can act, if any.
    let firstIncompleteField: String?
    let view: AnyView

    /// Tab order: the next field, or nil once focus belongs back in the search field.
    func fieldAfter(_ current: String?) -> String? {
        guard let current, let index = fieldNames.firstIndex(of: current) else {
            return fieldNames.first
        }
        return fieldNames.indices.contains(index + 1) ? fieldNames[index + 1] : nil
    }
}
