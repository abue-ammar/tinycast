import SwiftUI

/// A shortcut's optional input field in root search; left empty, the shortcut runs with no input.
@MainActor
enum AppleShortcutArgumentsAccessory {
    static func make(
        entryID: String,
        vm: PaletteState,
        metrics: InterfaceMetrics,
        focus: FocusState<String?>.Binding,
        onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory {
        let argument = InlineArgument(
            id: AppleShortcut.inputFieldID, title: String(localized: "Input"), isOptional: true)
        let key = PaletteState.argumentKey(entryID, argument.id)
        return PaletteHeaderAccessory(
            width: InlineArgumentFields.totalWidth(for: [argument], hasIcon: true, metrics: metrics),
            fieldNames: [argument.id],
            firstIncompleteField: nil,
            view: AnyView(
                InlineArgumentFields(
                    arguments: [argument], symbol: AppleShortcut.sfSymbol,
                    value: { _ in
                        Binding(
                            get: { vm.commandArguments[key] ?? "" },
                            set: { vm.commandArguments[key] = $0 })
                    },
                    focused: focus, openOptions: { _ in }, onSubmit: onSubmit
                )
                .id(entryID))
        )
    }

    static func values(forEntryID entryID: String, vm: PaletteState) -> [String: String] {
        let key = PaletteState.argumentKey(entryID, AppleShortcut.inputFieldID)
        guard let typed = vm.commandArguments[key], !typed.isEmpty else { return [:] }
        return [AppleShortcut.inputFieldID: typed]
    }
}
