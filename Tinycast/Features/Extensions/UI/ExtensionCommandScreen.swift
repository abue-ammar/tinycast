import QuartzCore
import SwiftUI

/// Restated here so launcher motion can change without moving an extension surface.
@MainActor private enum ExtensionMenuMotion {
    private static let entryScale: CGFloat = 0.94
    private static let exitScaleDelta: CGFloat = 0.04

    static let panel = MenuPanelMotion(
        entryScale: entryScale,
        maximumScale: 1.003,
        exitScaleDelta: exitScaleDelta,
        expansionDuration: 0.14,
        settleDuration: 0.08,
        exitDuration: 0.18,
        expansionTiming: CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1),
        settleTiming: CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1),
        exitTiming: CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1))
}

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

    /// A form's primary action stands even with no field to land on.
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

    /// The primary action is the panel's first `Action`.
    private func primaryAction(at selection: Int) -> ExtensionAction? {
        ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection)).first
    }

    var primaryActionTitle: String {
        primaryAction(at: vm.selection)?.title ?? "Run"
    }

    func hasPrimaryAction(at selection: Int) -> Bool { primaryAction(at: selection) != nil }

    /// A form usually ships one Submit action, and a one-row ⌘K panel is noise beside its pill.
    func hasActions(at selection: Int) -> Bool {
        guard isForm else { return true }
        return ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection)).count > 1
    }

    /// A form's pill stands even with no field to land on: the action belongs to the screen.
    var isForm: Bool {
        if case .form = screen.kind { return true }
        return false
    }

    /// A command's rows carry tinted icons and its panel scrolls; a menu row cannot.
    func menuContent(
        at selection: Int, query: String = "", menuSelection: Binding<Int>, onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent? {
        var actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection))
        guard !actions.isEmpty else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            actions = actions.compactMap { action -> (ExtensionAction, Int)? in
                guard let score = FuzzyMatch.score(query: trimmed, candidate: action.title) else { return nil }
                return (action, score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        }
        let screen = screen
        let assetsPath = assetsPath
        let extensions = extensions
        return PaletteMenuContent(
            rowCount: actions.count,
            view: { _ in
                AnyView(
                    ExtensionActionsPanel(
                        header: ExtensionActionsMenu.header(screen: screen, selection: selection),
                        items: ExtensionActionsMenu.rows(actions, assetsPath: assetsPath),
                        selection: menuSelection, isSearchable: true, onActivate: onActivate))
            },
            activate: { index in
                guard index >= 0, index < actions.count, let handler = actions[index].handler else { return }
                extensions.dispatch(handler: handler)
            },
            clipPath: { bounds, metrics, _ in
                UnevenRoundedRectangle(
                    topLeadingRadius: metrics.radius.menuPanel,
                    bottomLeadingRadius: metrics.radius.menuPanel,
                    bottomTrailingRadius: metrics.size.menuButton / 2,
                    topTrailingRadius: metrics.radius.menuPanel,
                    style: .continuous
                ).path(in: bounds).cgPath
            },
            motion: ExtensionMenuMotion.panel)
    }

    func activate(at selection: Int) {
        guard let handler = primaryAction(at: selection)?.handler else { return }
        extensions.dispatch(handler: handler)
    }

    func secondary(at selection: Int) -> Bool { false }

    /// The `searchBarAccessory` dropdown; an empty one states and opens nothing, so it is none.
    var searchAccessory: ExtensionSearchAccessory? {
        guard let accessory = ExtensionSearchAccessory(node: screen.searchBarAccessory),
            !accessory.items.isEmpty
        else { return nil }
        return accessory
    }

    /// The header control for it, as an opaque box the palette only seats and toggles.
    func searchAccessoryButton(
        _ accessory: ExtensionSearchAccessory, isOpen: Bool, action: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            ExtensionSearchAccessoryButton(
                accessory: accessory, value: extensions.accessorySelection(accessory),
                assetsPath: assetsPath, isOpen: isOpen, action: action))
    }

    /// Its choices as a palette menu, so the arrows, ↵, Escape and the click-away come free.
    func searchAccessoryMenu(
        menuSelection: Binding<Int>, onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent? {
        guard let accessory = searchAccessory else { return nil }
        let chosen = extensions.accessorySelection(accessory).map { Set([$0]) } ?? []
        let assetsPath = assetsPath
        let extensions = extensions
        return PaletteMenuContent(
            rowCount: accessory.items.count,
            view: { _ in
                AnyView(
                    ExtensionPickerList(
                        items: accessory.items, selection: menuSelection.wrappedValue,
                        chosen: chosen, assetsPath: assetsPath,
                        width: ExtensionSearchAccessoryButton.listWidth, onSelect: onActivate,
                        onHighlight: { menuSelection.wrappedValue = $0 }))
            },
            activate: { index in
                extensions.chooseAccessorySelection(accessory, value: accessory.items[index].value)
            },
            clipPath: { bounds, metrics, _ in
                RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous)
                    .path(in: bounds).cgPath
            },
            motion: ExtensionMenuMotion.panel)
    }

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
