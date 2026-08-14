import SwiftUI

/// The palette mode a running view command draws into.
///
/// `ExtensionScreen` decides the row order; this only adapts it to the palette, so the flat
/// `selection` index still maps 1:1 onto visible rows (see docs/features/palette.md).
struct ExtensionCommandScreen: PaletteScreen {
    let screen: ExtensionScreen
    let extensions: ExtensionManager
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    /// `assets/` of the running extension, so the icons it names resolve.
    var assetsPath: String? {
        guard let name = extensions.running?.extensionName,
            let owner = extensions.extensionNamed(name)
        else { return nil }
        return owner.assetsPath
    }

    /// Selectable rows only: a section header is drawn but never landed on.
    var rows: [RenderNode] { screen.items }

    /// A Grid needs both axes: ↑/↓ move a whole row, ←/→ move one cell. Without this the palette's
    /// linear step applies, and ↓ walked sideways through the grid one tile at a time.
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        guard case .grid(let columns) = screen.kind, columns > 0, !rows.isEmpty else { return nil }
        switch axis {
        case .vertical:
            let geometry = ExtensionGridGeometry(counts: screen.sectionCounts, columns: columns)
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

    func actions(at selection: Int) -> PopoverMenuContent? {
        ExtensionActionsMenu.content(
            screen: screen, selection: selection, assetsPath: assetsPath, core: core)
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
                onActivate: { activate(at: selection) },
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

    /// An extension action can declare its own shortcut; a modified keystroke is matched against the
    /// panel before the palette's own handling. Returns true when one fired.
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
