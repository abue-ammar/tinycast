import SwiftUI

struct EventEditorScreen: PaletteScreen {
    let coordinator: CalendarCoordinator
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    var rows: [MeetingEvent] { [] }
    let primaryActionTitle = "Create Event"
    let hidesSearchField = true
    let actsWithoutRows = true

    func hasPrimaryAction(at selection: Int) -> Bool { coordinator.editor != nil }
    func isPrimaryActionEnabled(at selection: Int) -> Bool { coordinator.editor?.draft.isValid == true }
    func hasActions(at selection: Int) -> Bool { false }
    func ownsVerticalKeys(at selection: Int) -> Bool { true }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        coordinator.editor?.advanceFocus(backwards: backwards)
        return true
    }

    func activate(at selection: Int) { coordinator.saveEvent() }
    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard let editor = coordinator.editor else { return AnyView(Color.clear) }
        return AnyView(
            EventEditorView(
                editor: editor, openMenuCorner: openMenuCorner, openInputMenu: openInputMenu
            )
            .id(ObjectIdentifier(editor))
            .environment(coordinator))
    }
}
