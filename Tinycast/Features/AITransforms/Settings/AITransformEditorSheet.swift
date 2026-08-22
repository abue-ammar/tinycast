import SwiftUI

/// Add / edit sheet for a single AI transform, presented from the AI Transforms pane.
struct AITransformEditorSheet: View {
    let transform: AITransform?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var name: String
    @State private var prompt: String
    @State private var iconSymbol: String?
    @State private var model: String
    @State private var providerAccountID: UUID?
    @State private var reasoningEffort: AIReasoningEffort?
    @State private var activationMode: AIExecutionMode?
    @State private var completionAction: AICompletionAction?
    @State private var showDiff: Bool
    @State private var fetchedModels: [String] = []
    @State private var forceCustomModel = false
    @State private var isFetchingModels = false
    @State private var showingIconPicker = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    init(transform: AITransform?) {
        self.transform = transform
        _name = State(initialValue: transform?.name ?? "")
        _prompt = State(initialValue: transform?.prompt ?? "")
        _iconSymbol = State(initialValue: transform?.iconSymbol)
        _model = State(initialValue: transform?.model ?? "")
        _providerAccountID = State(initialValue: transform?.providerAccountID)
        _reasoningEffort = State(initialValue: transform?.reasoningEffort)
        _activationMode = State(initialValue: transform?.activationMode)
        _completionAction = State(initialValue: transform?.completionAction)
        _showDiff = State(initialValue: transform?.showDiff ?? true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(transform == nil ? "Add AI Transform" : "Edit AI Transform")
                .font(.title2.weight(.bold))

            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Name")
                        .font(.callout.weight(.medium))
                    TextField("", text: $name, prompt: Text("Fix Spelling & Grammar"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .focused($nameFocused)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Icon")
                        .font(.callout.weight(.medium))
                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            SymbolImage(name: iconSymbol ?? AITransform.sfSymbol, size: 14)
                            Text(iconSymbol == nil ? "Default" : "Custom")
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 100)
                    }
                    .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                        AITransformIconPicker(selection: $iconSymbol) {
                            showingIconPicker = false
                        }
                    }
                }
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
                Text("Provider Account")
                    .font(.callout.weight(.medium))
                Picker("Provider Account", selection: $providerAccountID) {
                    Text("Inherit Default (\(defaultAccountName))").tag(nil as UUID?)
                    if !core.aiProviderAccounts.accounts.isEmpty {
                        Divider()
                        ForEach(core.aiProviderAccounts.accounts) { account in
                            Label {
                                Text(account.name)
                            } icon: {
                                AIProviderIcon(preset: account.providerPreset, size: 14)
                            }
                            .tag(account.id as UUID?)
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Reasoning / Thinking Level")
                    .font(.callout.weight(.medium))
                Picker("Reasoning Level", selection: $reasoningEffort) {
                    Text("Inherit Provider (\(inheritedReasoningTitle))").tag(nil as AIReasoningEffort?)
                    Divider()
                    ForEach(AIReasoningEffort.allCases) { effort in
                        Text(effort.title).tag(effort as AIReasoningEffort?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Activation Mode")
                    .font(.callout.weight(.medium))
                Picker("Activation Mode", selection: $activationMode) {
                    Text("Inherit Global (\(settings.aiExecutionMode.title))").tag(nil as AIExecutionMode?)
                    Divider()
                    ForEach(AIExecutionMode.allCases) { mode in
                        Text(mode.title).tag(mode as AIExecutionMode?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Action on Completion")
                    .font(.callout.weight(.medium))
                Picker("Action on Completion", selection: $completionAction) {
                    Text("Inherit Global (\(settings.aiCompletionAction.title))").tag(
                        nil as AICompletionAction?)
                    Divider()
                    ForEach(AICompletionAction.allCases) { action in
                        Text(action.title).tag(action as AICompletionAction?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Model Override")
                Text("Leave on Default to use the provider's default model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: Theme.Spacing.sm) {
                    Picker("Model Override", selection: modelSelection) {
                        Text("Default (\(defaultModelName))").tag(Self.defaultModelID)
                        if !fetchedModels.isEmpty {
                            Divider()
                            ForEach(fetchedModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        Divider()
                        Text("Custom…").tag(Self.customModelID)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

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
                .disabled(!isCustomModel)
                .opacity(isCustomModel ? 1.0 : 0.5)
            }
            Toggle(isOn: $showDiff) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text("Highlight differences")
                    Text(
                        "Show insertions and strikethroughs comparing with original text in interactive mode."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(transform == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task {
            refreshModels()
        }
        .onChange(of: providerAccountID) { _, _ in
            refreshModels()
        }
        .onAppear {
            if transform == nil {
                nameFocused = true
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }

    private func save() {
        // Editing keeps the UUID, and with it every reference the transform owns.
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = AITransform(
            id: transform?.id ?? UUID(),
            name: name,
            prompt: prompt,
            iconSymbol: iconSymbol,
            model: trimmedModel.isEmpty ? nil : trimmedModel,
            providerAccountID: providerAccountID,
            reasoningEffort: reasoningEffort,
            activationMode: activationMode,
            completionAction: completionAction,
            showDiff: showDiff
        )
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
    private var resolvedAccount: AIProviderAccount? {
        providerAccountID.flatMap(core.aiProviderAccounts.account(id:))
            ?? core.aiProviderAccounts.defaultAccount
    }

    private var defaultAccountName: String {
        core.aiProviderAccounts.defaultAccount?.name ?? "Default Provider"
    }

    private var inheritedReasoningTitle: String {
        resolvedAccount?.defaultReasoning.title ?? AIReasoningEffort.none.title
    }

    private var defaultModelName: String {
        resolvedAccount?.defaultModel.isEmpty == false
            ? resolvedAccount!.defaultModel
            : (settings.aiModel.isEmpty ? AIClient.defaultModel : settings.aiModel)
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

    private var modelSelection: Binding<String> {
        Binding(
            get: {
                isDefaultModel ? Self.defaultModelID : (isCustomModel ? Self.customModelID : model)
            },
            set: { selection in
                forceCustomModel = (selection == Self.customModelID)
                if selection == Self.defaultModelID {
                    model = ""
                } else if selection != Self.customModelID {
                    model = selection
                }
            })
    }

    private func refreshModels() {
        guard let account = resolvedAccount else { return }
        let key = SecretStore.secret(account: account.secretAccountKey) ?? ""
        guard account.isLocal || !key.isEmpty else { return }
        isFetchingModels = true
        Task {
            defer { isFetchingModels = false }
            fetchedModels = (try? await AIClient.listModels(baseURL: account.baseURL, apiKey: key)) ?? []
        }
    }
}

/// Curated grid of SF Symbols for AI Transforms with live search.
private struct AITransformIconPicker: View {
    @Binding var selection: String?
    let onPick: () -> Void
    @State private var query = ""

    private static let curatedSymbols = [
        "wand.and.stars", "sparkles", "bolt.fill", "brain.head.profile", "lightbulb.fill",
        "text.alignleft", "character.cursor.ibeam", "text.word.spacing", "pencil", "highlighter",
        "doc.text.fill", "doc.plaintext", "text.quote", "bubble.left.and.bubble.right.fill",
        "message.fill", "translate", "globe", "book.fill", "bookmark.fill", "graduationcap.fill",
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "hammer.fill",
        "wrench.and.screwdriver.fill",
        "ladybug.fill", "cpu.fill", "server.rack", "lock.shield.fill", "checklist", "list.bullet",
        "chart.bar.fill", "chart.pie.fill", "magnifyingglass", "eye.fill", "face.smiling",
        "heart.fill", "star.fill", "flame.fill", "paintbrush.fill", "scissors"
    ]

    private var filteredSymbols: [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return Self.curatedSymbols }
        return Self.curatedSymbols.filter { $0.lowercased().contains(trimmed) }
    }

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: Theme.Spacing.sm), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                selection = nil
                onPick()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: AITransform.sfSymbol, size: 14)
                    Text("Default (wand.and.stars)")
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search icons…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .background(Theme.Colors.controlSurface, in: .rect(cornerRadius: Theme.Radius.row))

            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            selection = symbol
                            onPick()
                        } label: {
                            SymbolImage(name: symbol, size: 15)
                                .frame(width: 30, height: 26)
                                .background(
                                    selection == symbol ? Theme.Colors.selection : Color.clear,
                                    in: .rect(cornerRadius: Theme.Radius.menu)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
            }
            .frame(maxHeight: 180)
        }
        .padding(Theme.Spacing.md)
        .frame(width: 260)
    }
}
