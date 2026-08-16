import SwiftUI

/// The inline argument fields Raycast shows beside the search field when the selected command declares
/// `arguments` — the command's icon, then one compact field per argument, filled before ↵ runs it.
///
/// Focus is deliberately separate from the search field's: the palette's whole focus model hangs off
/// one always-attached `TextField` (see docs/palette.md), so these get their own `FocusState` and Tab
/// hands focus back and forth rather than replacing it.
struct CommandArgumentsRow: View {
    let arguments: [ExtensionCommandArgument]
    /// The selected command's glyph, drawn as a leading chip so the fields read as belonging to it.
    let icon: EntryIcon?
    /// Binding factory keyed by argument name — the values live in the palette view's state.
    let value: (String) -> Binding<String>
    @FocusState.Binding var focused: String?
    /// ↵ from inside a field runs the command, like ↵ in the search field.
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let icon {
                EntryIconView(source: icon).frame(width: Self.height, height: Self.height)
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

    static let height: CGFloat = 26

    /// What the whole strip occupies, so the header can shrink the search field to exactly the room
    /// left over — the fields sit right after the typed text, as they do in Raycast.
    static func totalWidth(for arguments: [ExtensionCommandArgument], hasIcon: Bool) -> CGFloat {
        let fields = arguments.reduce(0) { $0 + fieldWidth(for: $1) }
        let gaps = CGFloat(arguments.count + (hasIcon ? 0 : -1)) * Theme.Spacing.xs
        return fields + gaps + (hasIcon ? height : 0)
    }

    static func fieldWidth(for argument: ExtensionCommandArgument) -> CGFloat {
        min(max(CGFloat(argument.placeholder.count) * 7 + 20, 62), 150)
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
        .font(Theme.Typography.rowTrailing)
        .tint(.white)
        .onSubmit(onSubmit)
        .multilineTextAlignment(.center)
        // Sized to the placeholder so a three-argument command (Hours / Minutes / Seconds) still fits.
        .frame(width: CommandArgumentsRow.fieldWidth(for: argument))
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(height: CommandArgumentsRow.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .onHover { hovered = $0 }
        .help(argument.required ? "\(argument.placeholder) — required" : argument.placeholder)
    }

    private var fill: Color {
        if isFocused { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Color.white.opacity(0.045)
    }

    /// Focus reads as a brighter edge; an unfilled required argument stays amber until it's answered.
    private var stroke: Color {
        if isFocused { return Color.white.opacity(0.28) }
        if argument.required && text.isEmpty { return Color.orange.opacity(0.45) }
        return Color.white.opacity(0.07)
    }
}
