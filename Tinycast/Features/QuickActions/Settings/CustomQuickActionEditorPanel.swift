import SwiftUI

struct CustomQuickActionEditRequest: Identifiable {
    let id = UUID()
    let action: CustomQuickAction?
}

struct CustomQuickActionEditorPanel: View {
    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(AppCore.self) private var core

    private let existing: CustomQuickAction?
    @State private var name: String
    @State private var iconSymbol: String?
    @State private var instructions: String
    @State private var model: AIModelSelection?
    @State private var failure: String?
    @State private var showingIconPicker = false

    private static let iconSymbols = [
        "wand.and.stars", "textformat", "text.append", "text.quote", "text.badge.checkmark",
        "character.cursor.ibeam", "scissors", "arrow.down.right.and.arrow.up.left", "list.bullet",
        "bubble.left.and.text.bubble.right", "envelope", "megaphone", "face.smiling",
        "theatermasks", "graduationcap", "book", "brain", "lightbulb", "sparkles", "checkmark.seal",
        "globe", "curlybraces", "terminal", "chart.bar", "tag", "flag", "bolt", "leaf",
        "paintbrush", "hammer", "heart", "star"
    ]

    private static let placeholder =
        "Make the text more concise, keeping the writer's voice and meaning."

    init(request: CustomQuickActionEditRequest, model: AIModelSelection?) {
        existing = request.action
        _name = State(initialValue: request.action?.name ?? "")
        _iconSymbol = State(initialValue: request.action?.iconSymbol)
        _instructions = State(initialValue: request.action?.instructions ?? "")
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: existing == nil ? "New Quick Action" : "Edit \(existing?.name ?? "")",
                subtitle: "Tinycast sends your selected text to the model with these instructions."
            )

            HStack(alignment: .bottom, spacing: Theme.Spacing.lg) {
                nameField
                iconField
            }

            instructionsField

            QuickActionModelPicker(selection: $model)

            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.destructive)
            }

            HStack(spacing: Theme.Spacing.md) {
                if let existing {
                    Button("Delete", role: .destructive) {
                        dismiss()
                        Task { await core.quickActionCoordinator.deleteCustomQuickAction(id: existing.id) }
                    }
                    .buttonStyle(.modalAction(.destructive, fillsWidth: false))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Name")
                .font(.callout.weight(.medium))
            TextField("Make Concise", text: $name)
                .settingsEditorTextField()
        }
    }

    private var iconField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Icon")
                .font(.callout.weight(.medium))
            Button {
                showingIconPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: iconSymbol ?? CustomQuickAction.sfSymbol, size: 14)
                    Text(iconSymbol == nil ? "Automatic" : "Custom")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: 120)
            }
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                SymbolPicker(
                    selection: $iconSymbol, fallback: CustomQuickAction.sfSymbol,
                    symbols: Self.iconSymbols
                ) {
                    showingIconPicker = false
                }
            }
        }
    }

    private var instructionsField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Instructions")
                .font(.callout.weight(.medium))
            TextEditor(text: $instructions)
                .font(.body)
                .settingsEditorTextArea(height: Theme.Size.editorTextHeight * 2)
                .overlay(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text(Self.placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(Theme.Spacing.md)
                            .allowsHitTesting(false)
                    }
                }
            Text(
                "Tinycast always tells the model to return only the transformed text, and to treat "
                    + "your selection as material rather than as instructions."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let draft = CustomQuickAction(
            id: existing?.id ?? UUID(), name: name, iconSymbol: iconSymbol,
            instructions: instructions,
            previewsResult: existing?.previewsResult ?? true,
            createdAt: existing?.createdAt ?? Date())
        do {
            if existing == nil {
                try core.quickActionCoordinator.addCustomQuickAction(draft, model: model)
            } else {
                try core.quickActionCoordinator.updateCustomQuickAction(draft, model: model)
            }
            dismiss()
        } catch {
            failure = error.errorDescription
        }
    }
}
