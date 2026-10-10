import SwiftUI

struct CustomCommandListScreen: PaletteScreen {
    let store: CustomCommandStore
    let coordinator: CustomCommandCoordinator
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let openActions: () -> Void

    let rows: [CustomCommand]
    var primaryActionTitle: String { rows.isEmpty ? "Create Custom Command" : "Run Command" }
    let actsWithoutRows = true

    init(
        store: CustomCommandStore, coordinator: CustomCommandCoordinator,
        vm: PaletteState, metrics: InterfaceMetrics, openActions: @escaping () -> Void
    ) {
        self.store = store
        self.coordinator = coordinator
        self.vm = vm
        self.metrics = metrics
        self.openActions = openActions
        rows = store.matching(vm.query)
    }

    private func command(at selection: Int) -> CustomCommand? {
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    var landingSelection: Int {
        guard let pending = vm.pendingArgumentEntryID else { return 0 }
        return rows.firstIndex { $0.entryID == pending } ?? 0
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        let selected = command(at: selection)
        var items =
            selected.map { command in
                CustomCommandActionsMenu.leadingItems(command: command, coordinator: coordinator) {
                    run(command)
                }
            } ?? []
        items.append(
            PopoverMenuItem(title: "Create Custom Command", systemImage: "plus", shortcut: "⌘N") {
                coordinator.editCustomCommand(nil)
            })
        if let command = selected {
            items.append(
                PopoverMenuItem(
                    title: "Delete Custom Command", systemImage: "trash", startsSection: true,
                    shortcut: "⌃X", isDestructive: true
                ) {
                    Task { await coordinator.deleteCustomCommand(id: command.id) }
                })
        }
        return PopoverMenuContent(header: selected?.name, items: items)
    }

    func activate(at selection: Int) {
        guard let command = command(at: selection) else {
            if rows.isEmpty { coordinator.editCustomCommand(nil) }
            return
        }
        run(command)
    }

    func secondary(at selection: Int) -> Bool { false }

    private func run(_ command: CustomCommand) {
        coordinator.runCustomCommand(
            id: command.id, values: CustomCommandArgumentsAccessory.values(for: command, vm: vm))
    }

    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        CustomCommandArgumentsAccessory.make(
            command: command(at: selection), vm: vm, metrics: metrics, focus: focus,
            onSubmit: { activate(at: selection) })
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .newItem {
            coordinator.editCustomCommand(nil)
            return true
        }
        guard let command = command(at: selection) else { return false }
        switch shortcut {
        case .edit: coordinator.editCustomCommand(command)
        case .delete: Task { await coordinator.deleteCustomCommand(id: command.id) }
        default: return false
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if rows.isEmpty {
            EmptyResults(
                text: store.commands.contains(where: \.isEnabled)
                    ? "No matching commands" : "No custom commands yet")
        } else {
            let selected = command(at: selection)
            HStack(spacing: 0) {
                CustomCommandList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { command in
                        if let index = rows.firstIndex(of: command) { vm.selection = index }
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { command in
                        if let index = rows.firstIndex(of: command) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                CustomCommandPreview(command: selected)
            }
        }
    }
}

@MainActor
enum CustomCommandActionsMenu {
    static func leadingItems(
        command: CustomCommand, coordinator: CustomCommandCoordinator,
        run: @escaping () -> Void
    ) -> [PopoverMenuItem] {
        [
            PopoverMenuItem(title: "Run Command", systemImage: command.symbol, shortcut: "↵", action: run),
            PopoverMenuItem(title: "Edit Custom Command", systemImage: "pencil", shortcut: "⌘E") {
                coordinator.editCustomCommand(command)
            }
        ]
    }
}
