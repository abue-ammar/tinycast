import AppKit
import SwiftUI

/// Asks for the `{argument}` values a snippet still needs, immediately before it expands.
@MainActor
enum SnippetArgumentsPrompt {
    /// The collected values, or nil on cancel. Modal: expansion is mid-flight and blocking.
    static func run(
        snippetName: String,
        arguments: [SnippetTemplateEngine.MissingArgument],
        metrics: InterfaceMetrics
    ) -> [String: String]? {
        guard !arguments.isEmpty else { return [:] }

        let values = ArgumentValues(arguments: arguments)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Snippet: \(snippetName)"
        alert.informativeText = "Fill in the template fields:"
        alert.alertStyle = .informational
        // AppKit gives ↵ to the first button and Esc to the one titled "Cancel".
        alert.addButton(withTitle: "Expand")
        alert.addButton(withTitle: "Cancel")

        let form = NSHostingView(
            rootView: SnippetArgumentsForm(values: values).environment(\.metrics, metrics))
        form.frame = NSRect(
            x: 0, y: 0,
            width: metrics.size.argumentPromptWidth,
            height: form.fittingSize.height)
        alert.accessoryView = form

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return values.collected
    }
}

/// Shared between the form and the caller, so `runModal()` can hand back what was typed.
@MainActor
@Observable
private final class ArgumentValues {
    let arguments: [SnippetTemplateEngine.MissingArgument]
    var entries: [String: String]

    init(arguments: [SnippetTemplateEngine.MissingArgument]) {
        self.arguments = arguments
        // An options list has no empty state, so it starts on its first choice.
        entries = arguments.reduce(into: [:]) { values, argument in
            values[argument.name] = argument.options.first ?? ""
        }
    }

    var collected: [String: String] { entries }

    func binding(for name: String) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.entries[name] ?? "" },
            set: { [weak self] newValue in self?.entries[name] = newValue })
    }
}

private struct SnippetArgumentsForm: View {

    @Environment(\.metrics) private var metrics
    let values: ArgumentValues
    @FocusState private var focusedArgument: String?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            ForEach(values.arguments, id: \.name) { argument in
                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    Text(argument.name)
                        .font(.callout.weight(.medium))
                    if argument.options.isEmpty {
                        TextField(argument.name, text: values.binding(for: argument.name))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedArgument, equals: argument.name)
                    } else {
                        Picker("", selection: values.binding(for: argument.name)) {
                            ForEach(argument.options, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Snippet argument \(argument.name)")
            }
        }
        .frame(width: metrics.size.argumentPromptWidth, alignment: .leading)
        // Focus the first text field so the prompt is typeable without a click.
        .onAppear { focusedArgument = values.arguments.first { $0.options.isEmpty }?.name }
    }
}
