import SwiftUI

/// Which arrow pair a move came from: ↑/↓ or ←/→.
enum PaletteAxis {
    case vertical
    case horizontal
}

/// A menu supplied by a palette screen, including its rendering and row activation.
@MainActor struct PaletteMenuContent {
    let rowCount: Int
    let isLoading: (Int) -> Bool
    /// Built on demand: `moveMenu` resolves the open menu on every arrow key.
    let view: () -> AnyView
    /// Bounds-checked by the caller against `rowCount`, so a row index is always one this menu has.
    let activate: (Int) -> Void

    init(
        rowCount: Int, view: @escaping () -> AnyView, activate: @escaping (Int) -> Void,
        isLoading: @escaping (Int) -> Bool = { _ in false }
    ) {
        self.rowCount = rowCount
        self.view = view
        self.activate = activate
        self.isLoading = isLoading
    }

    init(
        popover: PopoverMenuContent, selection: Binding<Int>, width: CGFloat = Theme.Size.menuWidth,
        onActivate: @escaping (Int) -> Void
    ) {
        self.init(
            rowCount: popover.items.count,
            view: {
                AnyView(
                    PopoverMenu(
                        header: popover.header, items: popover.items, selection: selection,
                        width: width, onActivate: onActivate))
            },
            activate: { popover.items[$0].action() },
            isLoading: { popover.items[$0].isLoading })
    }
}

/// One palette mode. `rows` is its single source of visible order, so selection indexes it.
@MainActor protocol PaletteScreen {
    associatedtype Row: Identifiable

    var rows: [Row] { get }
    var primaryActionTitle: String { get }

    /// False when the selection can't be acted on, which hides the footer pill and swallows ⌘K.
    func hasPrimaryAction(at selection: Int) -> Bool
    /// The ⌘K rows as the palette's own menu; nil when there are none.
    func actions(at selection: Int) -> PopoverMenuContent?
    /// Defaults to wrapping `actions(at:)`, so a screen implements one or the other.
    func menuContent(
        at selection: Int, menuSelection: Binding<Int>, onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent?
    func activate(at selection: Int)
    /// ⌘↵. False when the selection has no secondary action, leaving the key unhandled.
    func secondary(at selection: Int) -> Bool
    /// ⌥↵. False on every screen with nothing to paste, which is most of them.
    func pasteKeepingWindowOpen(at selection: Int) -> Bool
    /// The selection an arrow key lands on, or nil to leave the key to the palette's own default.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int?
    /// Controls the row wants beside the search field; `focus` is lent, never owned.
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    @ViewBuilder func body(selection: Int, scroll: ScrollIntent) -> AnyView
}

extension PaletteScreen {
    func hasPrimaryAction(at selection: Int) -> Bool { true }
    func actions(at selection: Int) -> PopoverMenuContent? { nil }
    func menuContent(
        at selection: Int, menuSelection: Binding<Int>, onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent? {
        guard let content = actions(at: selection) else { return nil }
        return PaletteMenuContent(
            popover: content, selection: menuSelection, onActivate: onActivate)
    }
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
