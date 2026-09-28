import SwiftUI

/// An installed tool's command path and launch variables, saved as each field is left.
struct AIProviderAdvancedSection: View {
    @Environment(AISettingsStore.self) private var settings

    let kind: InstalledAIKind
    /// What the lookup found, where Choose… opens.
    let detected: URL?

    @State private var path = ""
    @State private var variables: [Draft] = []
    @State private var saveFailed = false
    @State private var readFailed = false
    @FocusState private var focus: Field?

    private struct Draft: Identifiable, Equatable {
        let id = UUID()
        var name = ""
        var value = ""
    }

    private enum Field: Hashable {
        case path
        case name(UUID)
        case value(UUID)
    }

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Command path", text: $path, prompt: Text("Automatic"))
                        .labelsHidden()
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .focused($focus, equals: .path)
                        .onSubmit(save)
                    Button("Choose…", action: choose)
                        .fixedSize()
                }
            } label: {
                Text("Command path")
                Text("Empty finds \(kind.command) the way Terminal does.")
            }
            .task(id: kind) { load() }
            .onChange(of: focus) { old, new in
                if old != nil, old != new { save() }
            }
        } header: {
            Text("Command")
        }
        Section {
            LabeledContent {
                Button("Add Variable", action: addVariable)
                    .fixedSize()
                    .disabled(readFailed)
            } label: {
                Text("Variables")
                Text("Set for \(kind.title) only, each time it starts.")
            }
            ForEach($variables) { $variable in
                variableRow($variable)
            }
        } header: {
            Text("Environment")
        } footer: {
            Text(footer)
                .font(.caption)
                .foregroundStyle(
                    saveFailed || readFailed
                        ? AnyShapeStyle(Theme.Colors.destructive) : AnyShapeStyle(.secondary))
        }
    }

    private func variableRow(_ variable: Binding<Draft>) -> some View {
        let draft = variable.wrappedValue
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                TextField("Name", text: variable.name, prompt: Text("NAME"))
                    .labelsHidden()
                    .font(.callout.monospaced())
                    .autocorrectionDisabled()
                    .frame(width: Theme.Size.aiVariableName)
                    .focused($focus, equals: .name(draft.id))
                    .onSubmit(save)
                RevealableSecureField(
                    title: "Value of \(draft.name)", text: variable.value, prompt: Text("Value")
                )
                .labelsHidden()
                .font(.callout.monospaced())
                .focused($focus, equals: .value(draft.id))
                .onSubmit(save)
                Button {
                    remove(draft.id)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove")
                .accessibilityLabel("Remove \(draft.name)")
            }
            if let note = note(for: draft.name) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: String {
        if readFailed { return "The variables could not be read from your login Keychain." }
        return saveFailed
            ? "The variables could not be saved to your login Keychain."
            : "Values stay in your login Keychain. A change applies the next time \(kind.title) starts."
    }

    private func note(for name: String) -> String? {
        guard !name.isEmpty else { return nil }
        if !InstalledAILaunch.isVariableName(name) {
            return "A name is letters, digits and underscores, and does not start with a digit."
        }
        if kind.isManagedVariable(name) {
            return "Tinycast sets \(name) itself, so this value is not used."
        }
        return nil
    }

    private func load() {
        path = settings.override(for: kind).commandPath
        do {
            variables = try settings.environment(for: kind).map {
                Draft(name: $0.name, value: $0.value)
            }
            readFailed = false
        } catch {
            variables = []
            readFailed = true
        }
        saveFailed = false
    }

    private func save() {
        settings.setCommandPath(path, for: kind)
        // Drafts from a failed read have no values, and saving them would blank the stored ones.
        guard !readFailed else { return }
        do {
            try settings.setEnvironment(
                variables.map {
                    InstalledAIVariable(
                        name: $0.name.trimmingCharacters(in: .whitespaces), value: $0.value)
                }, for: kind)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    private func addVariable() {
        let draft = Draft()
        variables.append(draft)
        focus = .name(draft.id)
    }

    private func remove(_ id: UUID) {
        variables.removeAll { $0.id == id }
        save()
    }

    private func choose() {
        let start =
            detected?.deletingLastPathComponent()
            ?? FileManager.default.homeDirectoryForCurrentUser
        guard
            let url = ExecutablePicker.choose(
                message: "Choose the \(kind.command) command Tinycast should run.",
                startingAt: start)
        else { return }
        path = (url.path as NSString).abbreviatingWithTildeInPath
        save()
    }
}
