import SwiftUI

/// Add / edit sheet for a single AI transform, presented from the AI Transforms pane.
struct AITransformEditorSheet: View {
    let transform: AITransform?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var name: String
    @State private var prompt: String
    @State private var model: String
    @State private var fetchedModels: [String] = []
    @State private var forceCustomModel = false
    @State private var isFetchingModels = false
    @State private var errorMessage: String?
    init(transform: AITransform?) {
        self.transform = transform
        _name = State(initialValue: transform?.name ?? "")
        _prompt = State(initialValue: transform?.prompt ?? "")
        _model = State(initialValue: transform?.model ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(transform == nil ? "Add AI Transform" : "Edit AI Transform")
                .font(.title2.weight(.bold))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name")
                    .font(.callout.weight(.medium))
                TextField("", text: $name, prompt: Text("Fix Spelling & Grammar"))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Prompt")
                    .font(.callout.weight(.medium))
                TextEditor(text: $prompt)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.sm)
                    .frame(height: Theme.Size.editorTextHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )
            }

            Text(
                "The selected text is sent to the model as the message; this prompt is the "
                    + "instruction."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Model Override")
                            .font(.callout.weight(.medium))
                        Text("Leave on Default to use the provider's default model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: Theme.Spacing.sm) {
                        Picker(selection: modelSelection) {
                            Text("Default (\(defaultModelName))").tag(Self.defaultModelID)
                            if !fetchedModels.isEmpty {
                                Divider()
                                ForEach(fetchedModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            Divider()
                            Text("Custom…").tag(Self.customModelID)
                        } label: {
                            EmptyView()
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 160)

                        Button {
                            refreshModels()
                        } label: {
                            if isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .help("Fetch models from provider")
                        .disabled(isFetchingModels)
                    }
                }

                TextField(
                    "", text: $model,
                    prompt: Text(
                        isDefaultModel
                            ? "Using default (\(defaultModelName))"
                            : "Model ID (e.g. gemini-2.5-flash)"
                    )
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .disabled(isDefaultModel || (!isCustomModel && !fetchedModels.isEmpty))
                .opacity((isDefaultModel || (!isCustomModel && !fetchedModels.isEmpty)) ? 0.5 : 1.0)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task {
            if let key = SecretStore.secret(account: SecretStore.aiAPIKeyAccount), !key.isEmpty {
                isFetchingModels = true
                defer { isFetchingModels = false }
                do {
                    fetchedModels = try await AIClient.listModels(
                        baseURL: settings.aiBaseURL, apiKey: key)
                } catch {
                    fetchedModels = []
                }
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }

    private func save() {
        // Editing keeps the UUID, and with it every reference the transform owns.
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = AITransform(
            id: transform?.id ?? UUID(), name: name, prompt: prompt,
            model: trimmedModel.isEmpty ? nil : trimmedModel)
        do {
            if transform == nil {
                try core.aiTransformCoordinator.addTransform(draft)
            } else {
                try core.aiTransformCoordinator.updateTransform(draft)
            }
            dismiss()
        } catch {
            // Store validation (lengths, duplicate names) surfaces right here, inline.
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Model selection logic

    private static let defaultModelID = "default"
    private static let customModelID = "custom"

    private var isDefaultModel: Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isCustomModel: Bool {
        forceCustomModel || (!isDefaultModel && !fetchedModels.contains(model))
    }

    private var defaultModelName: String {
        settings.aiModel.isEmpty ? AIClient.defaultModel : settings.aiModel
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: {
                if isDefaultModel {
                    return Self.defaultModelID
                } else if isCustomModel {
                    return Self.customModelID
                } else {
                    return model
                }
            },
            set: { selection in
                if selection == Self.defaultModelID {
                    forceCustomModel = false
                    model = ""
                } else if selection == Self.customModelID {
                    forceCustomModel = true
                } else {
                    forceCustomModel = false
                    model = selection
                }
            })
    }

    private func refreshModels() {
        guard let key = SecretStore.secret(account: SecretStore.aiAPIKeyAccount), !key.isEmpty else {
            return
        }
        isFetchingModels = true
        Task {
            defer { isFetchingModels = false }
            do {
                fetchedModels = try await AIClient.listModels(
                    baseURL: settings.aiBaseURL, apiKey: key)
            } catch {
                fetchedModels = []
            }
        }
    }
}
