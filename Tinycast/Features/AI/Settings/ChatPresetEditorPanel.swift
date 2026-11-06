import SwiftUI

struct ChatPresetEditRequest: Identifiable {
    let id = UUID()
    let preset: ChatPreset?
}

struct ChatPresetEditorPanel: View {
    @Environment(\.settingsEditorDismiss) private var dismiss
    @Environment(AIChatCoordinator.self) private var coordinator

    private let existing: ChatPreset?
    @State private var name: String
    @State private var iconSymbol: String?
    @State private var instructions: String
    @State private var model: AIModelSelection?
    @State private var toolScope: ChatToolScope
    @State private var failure: String?
    @State private var showingIconPicker = false

    private static let iconSymbols = [
        "text.bubble", "bubble.left.and.bubble.right", "person.crop.circle", "brain", "lightbulb",
        "sparkles", "graduationcap", "book", "doc.text", "pencil.and.outline", "magnifyingglass",
        "chart.bar", "globe", "character.bubble", "curlybraces", "terminal", "ladybug", "hammer",
        "paintbrush", "megaphone", "envelope", "briefcase", "cart", "heart", "star", "flag", "leaf",
        "bolt"
    ]

    private static let placeholder = String(
        localized: "Describe the role, tone and format the model should follow in these chats.")

    init(request: ChatPresetEditRequest) {
        existing = request.preset
        _name = State(initialValue: request.preset?.name ?? "")
        _iconSymbol = State(initialValue: request.preset?.iconSymbol)
        _instructions = State(initialValue: request.preset?.instructions ?? "")
        _model = State(initialValue: request.preset?.model)
        _toolScope = State(initialValue: request.preset?.toolScope ?? ChatToolScope())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(
                title: existing == nil ? "New Chat Preset" : "Edit \(existing?.name ?? "")",
                subtitle: "Chats started from this preset use its instructions, model and tools.")

            HStack(alignment: .bottom, spacing: Theme.Spacing.lg) {
                nameField
                iconField
            }

            instructionsField

            modelField

            if !coordinator.mcpServers.isEmpty {
                toolsField
            }

            if let failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(Theme.Colors.destructive)
            }

            buttons
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface()
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Name")
                .font(.callout.weight(.medium))
            TextField("Writing Assistant", text: $name)
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
                    SymbolImage(name: iconSymbol ?? ChatPreset.sfSymbol, size: 14)
                    Text(iconSymbol == nil ? "Automatic" : "Custom")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(width: 120)
            }
            .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                SymbolPicker(
                    selection: $iconSymbol, fallback: ChatPreset.sfSymbol, symbols: Self.iconSymbols
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
            Text("Sent even when the system prompt is off, but never to Apple Intelligence.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Model")
                .font(.callout.weight(.medium))
            HStack(spacing: Theme.Spacing.lg) {
                AIModelSelectionRows(
                    selection: model,
                    inheritedTitle: String(localized: "Same as AI Chat"),
                    excludesOnDevice: true,
                    select: { model = $0 },
                    modelLabel: { Text("Model") },
                    effortLabel: { Text("Reasoning effort") })
            }
            .labelsHidden()
        }
    }

    private var toolsField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle("Use Tools", isOn: $toolScope.isEnabled)
                .font(.callout.weight(.medium))
            ForEach(coordinator.mcpServers) { server in
                Toggle(
                    server.name.isEmpty ? server.slug : server.name,
                    isOn: Binding(
                        get: { toolScope.allows(server.slug) },
                        set: { _ in toolScope.toggle(server.slug) }))
            }
            .disabled(!toolScope.isEnabled)
        }
        .toggleStyle(.checkbox)
    }

    private var buttons: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button("Cancel") { dismiss() }
                .buttonStyle(.modalAction(.cancel))
                .keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .buttonStyle(.modalAction(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let draft = ChatPreset(
            id: existing?.id ?? UUID(), name: name, iconSymbol: iconSymbol,
            instructions: instructions, model: model, toolScope: toolScope,
            createdAt: existing?.createdAt ?? Date())
        do {
            if existing == nil {
                try coordinator.addChatPreset(draft)
            } else {
                try coordinator.updateChatPreset(draft)
            }
            dismiss()
        } catch {
            failure = error.errorDescription
        }
    }
}
