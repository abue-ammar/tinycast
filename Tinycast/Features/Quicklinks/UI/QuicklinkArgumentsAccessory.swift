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
        let metrics = core.settings.interfaceSize.metrics
        let arguments = SnippetTemplateEngine.declaredArguments(in: quicklink.link).map {
            InlineArgument(
                id: $0.name, title: $0.name, options: $0.options, isOptional: $0.isOptional)
        }
        guard !arguments.isEmpty else { return nil }

        // Its own screen already shows the row the fields belong to, so the glyph would repeat it.
        let symbol = placement == .afterQuery ? quicklink.symbol : nil
        let value = { (name: String) in binding(quicklink: quicklink, name: name, vm: vm) }
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(
                for: arguments, hasIcon: symbol != nil, metrics: metrics),
            fieldNames: arguments.map(\.id),
            firstIncompleteField: arguments.first {
                !$0.isOptional && value($0.id).wrappedValue.isEmpty
            }?.id,
            optionsMenu: { id in
                guard let argument = arguments.first(where: { $0.id == id }),
                    !argument.options.isEmpty
                else { return nil }
                return menu(for: argument, value: value(id))
            },
            placement: placement,
            // Identity per row, so which fields were left unanswered resets on the next one.
            view: AnyView(
                InlineArgumentFields(
                    arguments: arguments, symbol: symbol, value: value, focused: focus,
                    openOptions: onOpenOptions, onSubmit: onSubmit
                )
                .id(quicklink.entryID))
        )
    }

    static func values(for quicklink: Quicklink, vm: PaletteState) -> [String: String] {
        var values: [String: String] = [:]
        for argument in SnippetTemplateEngine.declaredArguments(in: quicklink.link) {
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
        for argument: InlineArgument, value: Binding<String>
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: argument.title,
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
