import SwiftUI

/// A custom command's inline fields in root search, keyed by `$n` rather than by name.
@MainActor
enum CustomCommandArgumentsAccessory {
    static func make(
        command: CustomCommand?,
        vm: PaletteState,
        metrics: InterfaceMetrics,
        focus: FocusState<String?>.Binding,
        onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let command, !command.arguments.isEmpty else { return nil }
        let arguments = command.arguments.enumerated().map { index, argument in
            InlineArgument(
                id: CustomCommandArgument.fieldID(at: index), title: argument.name,
                isOptional: argument.isOptional)
        }
        let value = { (id: String) in binding(command: command, id: id, vm: vm) }
        let firstOwed = {
            arguments.first { !$0.isOptional && value($0.id).wrappedValue.isEmpty }?.id
        }
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(for: arguments, hasIcon: true, metrics: metrics),
            fieldNames: arguments.map(\.id),
            firstIncompleteField: firstOwed(),
            // Identity per row, so "which fields were left unanswered" starts clean on the next one.
            view: AnyView(
                InlineArgumentFields(
                    arguments: arguments, symbol: command.symbol, value: value, focused: focus,
                    openOptions: { _ in },
                    // Raycast's rule: ↵ never runs short, it moves to the required field instead.
                    onSubmit: {
                        guard let owed = firstOwed() else { return onSubmit() }
                        focus.wrappedValue = owed
                    }
                )
                .id(command.entryID))
        )
    }

    /// The typed values keyed by field, stripped of blanks, plus the matched alias input.
    static func values(for command: CustomCommand, vm: PaletteState) -> [String: String] {
        var values: [String: String] = [:]
        for index in command.arguments.indices {
            let id = CustomCommandArgument.fieldID(at: index)
            let typed = vm.commandArguments[PaletteState.argumentKey(command.entryID, id)] ?? ""
            if !typed.isEmpty { values[id] = typed }
        }
        // Stored when a shortcut-less run was sent back to the fields, where the query is just the name.
        let kept = vm.commandArguments[PaletteState.argumentKey(command.entryID, CustomCommand.inputValueKey)]
        if let input = command.matchedInput(for: vm.query) ?? kept {
            values[CustomCommand.inputValueKey] = input
        }
        return values
    }

    private static func binding(
        command: CustomCommand, id: String, vm: PaletteState
    ) -> Binding<String> {
        let key = PaletteState.argumentKey(command.entryID, id)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }
}
