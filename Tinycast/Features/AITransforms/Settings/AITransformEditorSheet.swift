import SwiftUI

/// Add / edit sheet for a single AI transform, presented from the AI Transforms pane.
struct AITransformEditorSheet: View {
    let transform: AITransform?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @State private var name: String
    @State private var prompt: String
    @State private var model: String
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
                TextField("Fix Spelling & Grammar", text: $name)
                    .textFieldStyle(.roundedBorder)
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

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Model Override")
                    .font(.callout.weight(.medium))
                TextField("Leave empty to use the default model", text: $model)
                    .textFieldStyle(.roundedBorder)
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
}
