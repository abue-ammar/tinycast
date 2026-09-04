import SwiftUI

/// `ExtensionScreen` decides the row order; this maps `selection` 1:1 onto visible rows.
struct ExtensionCommandScreen: PaletteScreen {
    let screen: ExtensionScreen
    let extensions: ExtensionManager
    let vm: PaletteState
    let openActions: () -> Void

    /// `assets/` of the running extension, so the icons it names resolve.
    var assetsPath: String? {
        guard let name = extensions.running?.extensionName,
            let owner = extensions.extensionNamed(name)
        else { return nil }
        return owner.assetsPath
    }

    /// Selectable rows only: a section header is drawn but never landed on, and so is a separator.
    var rows: [ExtensionScreen.Item] { screen.items }

    /// A form owns the whole keyboard: its fields are the text, so the search field steps aside.
    var hidesSearchField: Bool { isForm }

    /// ↵ submits a form whether or not it has a field to land on.
    var actsWithoutRows: Bool { isForm }

    /// A text area edits with ↑/↓ itself, so only ⇥ leaves it.
    func ownsVerticalKeys(at selection: Int) -> Bool {
        guard isForm, rows.indices.contains(selection) else { return false }
        return ExtensionFormField(type: rows[selection].node.type).ownsVerticalKeys
    }

    /// ⇥ / ⇧⇥ walk the fields, wrapping at either end as Raycast's form does.
    func tabTarget(from selection: Int, backwards: Bool) -> Int? {
        guard isForm, !rows.isEmpty else { return nil }
        return (selection + (backwards ? -1 : 1) + rows.count) % rows.count
    }

    /// A Grid needs both axes: without this ↓ walks sideways one tile at a time.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        guard case .grid(let layout) = screen.kind, !rows.isEmpty else { return nil }
        switch axis {
        case .vertical:
            let geometry = ExtensionGridGeometry(
                counts: screen.sectionCounts, columns: layout.columns)
            return delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        case .horizontal:
            return min(max(selection + delta, 0), rows.count - 1)
        }
    }

    /// The panel's first `Action`, exactly as in Raycast.
    private func primaryAction(at selection: Int) -> ExtensionAction? {
        ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection)).first
    }

    var primaryActionTitle: String {
        primaryAction(at: vm.selection)?.title ?? "Run"
    }

    func hasPrimaryAction(at selection: Int) -> Bool { primaryAction(at: selection) != nil }

    /// A form usually ships one Submit action, and a one-row ⌘K panel is noise beside the ↵ pill.
    func hasActions(at selection: Int) -> Bool {
        ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection)).count > 1
    }

    /// A form's ↵ pill stands even with no field to land on: the action belongs to the screen.
    var isForm: Bool {
        if case .form = screen.kind { return true }
        return false
    }

    /// A command's rows carry tinted icons and its panel scrolls; a menu row cannot.
    func menuContent(
        at selection: Int, menuSelection: Binding<Int>, onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent? {
        let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection))
        guard !actions.isEmpty else { return nil }
        let screen = screen
        let assetsPath = assetsPath
        let extensions = extensions
        return PaletteMenuContent(
            rowCount: actions.count,
            view: {
                AnyView(
                    ExtensionActionsPanel(
                        header: ExtensionActionsMenu.header(screen: screen, selection: selection),
                        items: ExtensionActionsMenu.rows(actions, assetsPath: assetsPath),
                        selection: menuSelection, onActivate: onActivate))
            },
            activate: { index in
                guard let handler = actions[index].handler else { return }
                extensions.dispatch(handler: handler)
            })
    }

    func activate(at selection: Int) {
        guard let handler = primaryAction(at: selection)?.handler else { return }
        extensions.dispatch(handler: handler)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ExtensionCommandView(
                screen: screen,
                state: extensions.state,
                selection: selection,
                assetsPath: assetsPath,
                scroll: scroll,
                onSelect: { vm.selection = $0 },
                onActivate: { activate(at: $0) },
                onActions: { index in
                    vm.selection = index
                    openActions()
                },
                onFieldChange: { field, value in
                    guard let handler = field.handler("onTinycastChange") else { return }
                    extensions.dispatch(handler: handler, arguments: [value])
                }
            ))
    }

    /// Matched before the palette's own handling; true when an action fired.
    func dispatchShortcut(key: KeyEquivalent, modifiers: EventModifiers, at selection: Int) -> Bool {
        let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection))
        guard
            let handler = actions.first(where: { $0.matches(key: key, modifiers: modifiers) })?
                .handler
        else { return false }
        extensions.dispatch(handler: handler)
        return true
    }
}
