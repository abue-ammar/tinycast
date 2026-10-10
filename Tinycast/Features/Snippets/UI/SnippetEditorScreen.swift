import SwiftUI

struct SnippetEditorScreen: PaletteScreen {
    let coordinator: SnippetCoordinator
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    var rows: [StoredSnippet] { [] }
    var primaryActionTitle: String { coordinator.editor?.isSaving == true ? "Saving…" : "Save Snippet" }
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

    func activate(at selection: Int) { coordinator.requestSnippetSave() }
    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard let editor = coordinator.editor else { return AnyView(Color.clear) }
        return AnyView(
            SnippetEditorView(editor: editor, openInputMenu: openInputMenu)
                .id(ObjectIdentifier(editor))
                .environment(coordinator))
    }
}
