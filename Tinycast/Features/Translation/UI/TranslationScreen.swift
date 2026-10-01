import SwiftUI

/// The translator as a palette mode: no rows, no search field, and the keyboard in two text views.
struct TranslationScreen: PaletteScreen {
    let coordinator: TranslationCoordinator
    let vm: PaletteState
    let toggleActions: () -> Void

    var rows: [AppEntry] { [] }
    var primaryActionTitle: String { "Copy Translation" }
    var hidesSearchField: Bool { true }
    var actsWithoutRows: Bool { true }

    func hasPrimaryAction(at selection: Int) -> Bool { coordinator.canCopy }

    /// Both columns edit or select with ↑/↓ themselves; only ⇥ leaves one, for the other.
    func ownsVerticalKeys(at selection: Int) -> Bool { true }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        TranslationTextView.cycleFocus(backwards: backwards)
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? { coordinator.actionsMenu }

    /// Safe with nothing to copy: the coordinator copies only a translation matching the draft.
    func activate(at selection: Int) { coordinator.copyTranslation() }

    func secondary(at selection: Int) -> Bool {
        coordinator.copyTranslation()
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(TranslationView(toggleActions: toggleActions))
    }
}
