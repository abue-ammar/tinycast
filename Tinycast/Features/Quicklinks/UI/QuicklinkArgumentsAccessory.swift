import SwiftUI

/// The inline argument strip, as a `PaletteHeaderAccessory` the palette renders without reading.
@MainActor
enum QuicklinkArgumentsAccessory {
    /// Nil when the selected quicklink asks for nothing, which is every link without a placeholder.
    static func make(
        quicklink: Quicklink?,
        core: AppCore,
        vm: PaletteState,
        focus: FocusState<String?>.Binding,
        placement: PaletteHeaderAccessory.Placement,
        onOpenOptions: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let quicklink else { return nil }
        let arguments = core.quicklinkCoordinator.promptedArguments(for: quicklink)
        guard !arguments.isEmpty else { return nil }

        // Its own screen already shows the row the fields belong to, so the glyph would repeat it.
        let symbol = placement == .afterQuery ? quicklink.symbol : nil
        let value = { (name: String) in binding(quicklink: quicklink, name: name, vm: vm) }
        return PaletteHeaderAccessory(
            width: QuicklinkArgumentsRow.totalWidth(for: arguments, hasIcon: symbol != nil),
            fieldNames: arguments.map(\.name),
            firstIncompleteField: arguments.first { value($0.name).wrappedValue.isEmpty }?.name,
            optionsMenu: { name in
                guard let argument = arguments.first(where: { $0.name == name }),
                    !argument.options.isEmpty
                else { return nil }
                return menu(for: argument, value: value(name))
            },
            placement: placement,
            view: AnyView(
                QuicklinkArgumentsRow(
                    arguments: arguments, symbol: symbol, value: value, focused: focus,
                    openOptions: onOpenOptions, onSubmit: onSubmit))
        )
    }

    /// The typed values for one quicklink, stripped of blanks — what the open funnel is handed.
    static func values(for quicklink: Quicklink, core: AppCore, vm: PaletteState) -> [String: String] {
        var values: [String: String] = [:]
        for argument in core.quicklinkCoordinator.promptedArguments(for: quicklink) {
            let typed =
                vm.commandArguments[
                    PaletteState.argumentKey(quicklink.entryID, argument.name)] ?? ""
            if !typed.isEmpty { values[argument.name] = typed }
        }
        return values
    }

    private static func binding(
        quicklink: Quicklink, name: String, vm: PaletteState
    ) -> Binding<String> {
        let key = PaletteState.argumentKey(quicklink.entryID, name)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }

    private static func menu(
        for argument: SnippetTemplateEngine.MissingArgument, value: Binding<String>
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: argument.name,
            items: argument.options.map { option in
                PopoverMenuItem(
                    title: option,
                    icon: value.wrappedValue == option ? .symbol("checkmark") : .blank
                ) {
                    value.wrappedValue = option
                }
            })
    }
}
