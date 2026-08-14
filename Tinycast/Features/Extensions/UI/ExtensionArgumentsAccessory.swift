import SwiftUI

/// Builds the inline argument strip a launcher row shows when its command declares arguments.
///
/// The palette asks a screen for a `PaletteHeaderAccessory` and renders whatever comes back. Every
/// part that is extension-shaped — which arguments exist, how wide their fields are, which one is
/// still empty — is decided here, so the header's layout maths never lived in `RootPaletteView`.
@MainActor
enum ExtensionArgumentsAccessory {
    /// Nil when the row declares no arguments, which is every row but an extension command's.
    static func make(
        entry: AppEntry?,
        coordinator: ExtensionCoordinator,
        values: @escaping (String) -> Binding<String>,
        focus: FocusState<String?>.Binding,
        onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let entry, let arguments = coordinator.commandArguments(for: entry),
            !arguments.isEmpty
        else { return nil }

        let icon = entry.iconSource
        return PaletteHeaderAccessory(
            width: CommandArgumentsRow.totalWidth(for: arguments, hasIcon: true),
            fieldNames: arguments.map(\.name),
            firstIncompleteField: arguments.first {
                $0.required && values($0.name).wrappedValue.isEmpty
            }?.name,
            view: AnyView(
                CommandArgumentsRow(
                    arguments: arguments, icon: icon, value: values, focused: focus,
                    onSubmit: onSubmit)))
    }
}
