import SwiftUI

struct CustomCommandEditorScreen: PaletteScreen {
    let coordinator: CustomCommandCoordinator
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    var rows: [CustomCommand] { [] }
    let primaryActionTitle = "Save Command"
    let hidesSearchField = true
    let actsWithoutRows = true

    func hasPrimaryAction(at selection: Int) -> Bool { coordinator.editor != nil }
    func isPrimaryActionEnabled(at selection: Int) -> Bool { coordinator.editor?.canSave == true }
    func hasActions(at selection: Int) -> Bool { false }
    func ownsVerticalKeys(at selection: Int) -> Bool { true }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        coordinator.editor?.advanceFocus(backwards: backwards)
        return true
    }

    func activate(at selection: Int) { coordinator.saveCustomCommand() }
    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard let editor = coordinator.editor else { return AnyView(Color.clear) }
        return AnyView(
            CustomCommandEditorView(
                editor: editor, openMenuCorner: openMenuCorner, openInputMenu: openInputMenu
            )
            .id(ObjectIdentifier(editor))
            .environment(coordinator))
    }
}
