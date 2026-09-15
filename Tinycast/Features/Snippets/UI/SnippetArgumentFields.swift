import SwiftUI

/// The `{argument}` values a snippet still needs; reference semantics let the caller read them back.
@MainActor
@Observable
final class SnippetArgumentsState {
    let arguments: [SnippetTemplateEngine.MissingArgument]
    var values: [String: String]

    init(arguments: [SnippetTemplateEngine.MissingArgument]) {
        self.arguments = arguments
        // An options list has no empty state, so it starts on its first choice.
        values = arguments.reduce(into: [:]) { values, argument in
            values[argument.name] = argument.options.first ?? ""
        }
    }
}

/// The snippet argument dialog's controls: a field per free argument, chips per options list.
struct SnippetArgumentFields: View {
    @Environment(\.metrics) private var metrics
    let state: SnippetArgumentsState
    @FocusState private var focusedArgument: String?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xl) {
            ForEach(state.arguments, id: \.name) { argument in
                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    Text(argument.name)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if argument.options.isEmpty {
                        TextField(
                            "", text: value(for: argument.name),
                            prompt: Text(argument.name)
                        )
                        .focused($focusedArgument, equals: argument.name)
                        .dialogTextField()
                    } else {
                        OptionChips(
                            options: argument.options,
                            selection: value(for: argument.name))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Snippet argument \(argument.name)")
            }
        }
        .onAppear { focusedArgument = state.arguments.first { $0.options.isEmpty }?.name }
    }

    private func value(for name: String) -> Binding<String> {
        Binding(get: { state.values[name] ?? "" }, set: { state.values[name] = $0 })
    }
}

private struct OptionChips: View {
    @Environment(\.metrics) private var metrics
    let options: [String]
    @Binding var selection: String

    var body: some View {
        // A list too long for one row stacks, rather than running past the dialog's edge.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: metrics.spacing.md) { chips }
            VStack(alignment: .leading, spacing: metrics.spacing.md) { chips }
        }
    }

    /// Indexed, since nothing stops an `options=` list from repeating a value.
    private var chips: some View {
        ForEach(options.indices, id: \.self) { index in
            DialogChip(title: options[index], selected: options[index] == selection) {
                selection = options[index]
            }
        }
    }
}
