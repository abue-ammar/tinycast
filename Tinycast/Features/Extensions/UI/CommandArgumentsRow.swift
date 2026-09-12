import SwiftUI

/// The inline argument fields beside the search field; their own `FocusState`, Tab hands over.
struct CommandArgumentsRow: View {
    @Environment(\.metrics) private var metrics
    let arguments: [ExtensionCommandArgument]
    /// The selected command's glyph, drawn as a leading chip so the fields read as belonging to it.
    let icon: EntryIcon?
    /// Binding factory keyed by argument name — the values live in the palette view's state.
    let value: (String) -> Binding<String>
    @FocusState.Binding var focused: String?
    /// ↵ from inside a field runs the command, like ↵ in the search field.
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            if let icon {
                EntryIconView(source: icon)
                    .frame(width: Self.height(metrics), height: Self.height(metrics))
            }
            ForEach(arguments, id: \.name) { argument in
                ArgumentField(
                    argument: argument,
                    text: value(argument.name),
                    isFocused: focused == argument.name,
                    onSubmit: onSubmit
                )
                .focused($focused, equals: argument.name)
            }
        }
    }

    static func height(_ metrics: InterfaceMetrics) -> CGFloat { metrics.scaled(26) }

    /// The header shrinks the search field to exactly the room left over.
    static func totalWidth(
        for arguments: [ExtensionCommandArgument], hasIcon: Bool, metrics: InterfaceMetrics
    ) -> CGFloat {
        let fields = arguments.reduce(0) { $0 + fieldWidth(for: $1, metrics: metrics) }
        let gaps = CGFloat(arguments.count + (hasIcon ? 0 : -1)) * metrics.spacing.xs
        return fields + gaps + (hasIcon ? height(metrics) : 0)
    }

    static func fieldWidth(
        for argument: ExtensionCommandArgument, metrics: InterfaceMetrics
    )
        -> CGFloat
    {
        let placeholder = CGFloat(argument.placeholder.count) * metrics.scaled(7)
        return min(max(placeholder + metrics.scaled(20), metrics.scaled(62)), metrics.scaled(150))
    }

    /// The order Tab walks: search field (nil) → each argument → back to the search field.
    static func next(after current: String?, in arguments: [ExtensionCommandArgument]) -> String? {
        guard let current, let index = arguments.firstIndex(where: { $0.name == current }) else {
            return arguments.first?.name
        }
        let following = arguments.index(after: index)
        return following < arguments.endIndex ? arguments[following].name : nil
    }
}

private struct ArgumentField: View {

    @Environment(\.metrics) private var metrics
    let argument: ExtensionCommandArgument
    @Binding var text: String
    let isFocused: Bool
    let onSubmit: () -> Void
    @State private var hovered = false

    var body: some View {
        TextField(
            "", text: $text,
            prompt: Text(argument.placeholder).foregroundStyle(Theme.Colors.textTertiary)
        )
        .textFieldStyle(.plain)
        .font(metrics.typography.rowTrailing)
        .tint(.white)
        .onSubmit(onSubmit)
        .multilineTextAlignment(.center)
        // Sized to the placeholder so a three-argument command still fits.
        .frame(width: CommandArgumentsRow.fieldWidth(for: argument, metrics: metrics))
        .padding(.horizontal, metrics.spacing.sm)
        .frame(height: CommandArgumentsRow.height(metrics))
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .onHover { hovered = $0 }
        .help(argument.required ? "\(argument.placeholder) — required" : argument.placeholder)
    }

    private var fill: Color {
        if isFocused { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return ExtensionColors.fieldFill
    }

    /// Focus reads as a brighter edge; an unfilled required argument stays amber.
    private var stroke: Color {
        if isFocused { return ExtensionColors.fieldFocusStroke }
        if argument.required && text.isEmpty { return Color.orange.opacity(0.45) }
        return ExtensionColors.fieldStroke
    }
}
