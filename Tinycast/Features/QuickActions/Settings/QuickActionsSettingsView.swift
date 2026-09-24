import Combine
import SwiftUI

/// A peer of the AI pane, not a section in it: it only borrows the provider layer.
struct QuickActionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var appSettings
    @Environment(QuickActionSettingsStore.self) private var store
    @Environment(CustomQuickActionStore.self) private var customActions
    @Environment(AISettingsStore.self) private var aiSettings
    @Environment(VisibilityStore.self) private var visibility

    /// Polled like the Permissions pane: the grant lands in System Settings, which sends nothing.
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    @State private var editingAction: BuiltInQuickAction?
    @State private var customEditing: CustomQuickActionEditRequest?
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .quickActionsQuickActions, title: "Enable Quick Actions",
                        subtitle: "Act on selected text. Nothing is read until you press a shortcut.")
                }
                if appSettings.quickActionsEnabled, !isTrusted {
                    // Every shortcut fails without it; better said here than found one press later.
                    SettingsRow(
                        title: "Accessibility permission required",
                        subtitle: "Needed to read your selection."
                    ) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.destructive)
                            .frame(width: Theme.Size.settingsRowIcon)
                    } trailing: {
                        Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                    }
                }
            } header: {
                SettingsSectionHeader(.quickActionsQuickActions)
            }

            Group {
                actionsSection
                modelSection
                languageSection
            }
            .settingsEnabled(appSettings.quickActionsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.quickActions)
        .onReceive(refreshTimer) { _ in isTrusted = Permissions.isAccessibilityTrusted() }
        .settingsEditorPanel(item: $editingAction) { action in
            InstructionsEditorPanel(
                action: action,
                instructionOverride: store.settings.instructionOverride(for: action),
                modelOverride: store.modelOverride(for: .builtIn(action))
            ) { instructionOverride, modelOverride in
                store.settings.setInstructionOverride(instructionOverride, for: action)
                store.setModelOverride(modelOverride, for: .builtIn(action))
            }
        }
        .settingsEditorPanel(item: $customEditing) { request in
            CustomQuickActionEditorPanel(
                request: request,
                model: request.action.flatMap { store.modelOverride(for: .custom($0)) })
        }
        .onAppear {
            core.quickActionCoordinator.loadLanguages()
            store.repairModel(against: aiSettings.connections, fallback: aiSettings.defaultModel)
            store.resolveModel(
                appleIntelligenceAvailable: aiSettings.isAppleIntelligenceAvailable(),
                fallback: aiSettings.defaultModel)
            core.applyInstalledAILifecycle()
        }
        .onChange(of: appSettings.aiEnabled) { repairInstalledModel() }
        .onChange(of: aiSettings.enabledInstalledProviders) {
            core.applyInstalledAILifecycle()
            repairInstalledModel()
        }
        .onChange(of: core.chatGPTSubscription.models) { repairInstalledModel() }
        .onChange(of: core.chatGPTSubscription.phase) { repairInstalledModel() }
        .onChange(of: core.installedAI.statuses) { repairInstalledModel() }
    }

    private var actionsSection: some View {
        Section {
            ForEach(BuiltInQuickAction.allCases, content: builtInRow)
            ForEach(customActions.actions) { action in
                SettingsRow(title: action.name, subtitle: subtitle(for: .custom(action))) {
                    SymbolImage(name: action.symbol, size: Theme.Size.quickActionHeaderIcon)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    editButton(title: action.name) {
                        customEditing = CustomQuickActionEditRequest(action: action)
                    }
                    AliasField(key: action.entryID, name: action.name)
                    ShortcutRecorder(action: .quickAction(id: action.id), isQuiet: true)
                    resultPicker(title: action.name, selection: previewBinding(action))
                    launcherToggle(title: action.name, entry: AppEntry(action))
                }
            }
            Button {
                customEditing = CustomQuickActionEditRequest(action: nil)
            } label: {
                SettingsRowTitle(.quickActionsActions, "Add Quick Action")
            }
        } header: {
            SettingsSectionHeader(.quickActionsActions)
        } footer: {
            Text("Replace writes into your document, and undo restores it. Preview shows a panel first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func builtInRow(_ action: BuiltInQuickAction) -> some View {
        let entry = CommandCatalog.entry(for: CommandID(action))
        return SettingsRow(title: action.title, subtitle: subtitle(for: .builtIn(action))) {
            Image(systemName: action.symbol)
                .frame(width: Theme.Size.settingsRowIcon)
        } trailing: {
            if !action.usesTranslationFramework {
                editButton(title: action.title) { editingAction = action }
            }
            // The four left the Commands pane with their kind, and its alias field with it.
            if let entry { AliasField(entry: entry) }
            ShortcutRecorder(action: .command(CommandID(action)), isQuiet: true)
            resultPicker(title: action.title, selection: previewBinding(action))
                .disabled(action.alwaysPreviews)
            if let entry { launcherToggle(title: action.title, entry: entry) }
        }
    }

    private func editButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SymbolImage(name: "pencil", size: Theme.Size.quickActionHeaderIcon)
        }
        .buttonStyle(.plain)
        .help("Edit \(title)")
        .accessibilityLabel("Edit \(title)")
    }

    private func resultPicker(title: String, selection: Binding<Bool>) -> some View {
        Picker("", selection: selection) {
            Text("Replace").tag(false)
            Text("Preview").tag(true)
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("What \(title) does with its result")
    }

    private func launcherToggle(title: String, entry: AppEntry) -> some View {
        Toggle("", isOn: launcherBinding(entry))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .launcherVisibilityHelp()
            .accessibilityLabel("Show \(title) in launcher")
    }

    private var modelSection: some View {
        Section {
            AIModelSelectionRows(
                selection: store.model,
                select: store.select,
                modelLabel: {
                    SettingsRowTitle(.quickActionsModel, "Model")
                    Text("Unless an action sets its own.")
                },
                effortLabel: {
                    SettingsRowTitle(.quickActionsModel, "Reasoning effort")
                }
            )
        } header: {
            SettingsSectionHeader(.quickActionsModel)
        } footer: {
            Text("Separate from AI Chat's, so frequent use needn't bill an API.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: languageBinding) {
                Text("Same as this Mac").tag("")
                ForEach(core.quickActionCoordinator.offeredLanguages, id: \.minimalIdentifier) {
                    Text(TextTranslator.displayName(of: $0)).tag($0.minimalIdentifier)
                }
            } label: {
                SettingsRowTitle(.quickActionsTranslate, "Translate to")
            }
        } header: {
            SettingsSectionHeader(.quickActionsTranslate)
        } footer: {
            Text("Apple's translator, on this Mac. A language downloads on first use.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for action: QuickAction) -> String? {
        let details = [
            action.alwaysPreviews ? "Always shown in a panel" : nil,
            store.modelOverride(for: action).map(routeTitle)
        ].compactMap(\.self)
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private func routeTitle(_ selection: AIModelSelection) -> String {
        let model = modelChoices.first { $0.matches(selection) }?.title ?? selection.model
        guard let effort = selection.effort else { return model }
        return "\(model) (\(ChatGPTSubscription.Effort(id: effort, detail: nil).title))"
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { appSettings.quickActionsEnabled },
            set: { core.quickActionCoordinator.setEnabled($0) })
    }

    private func previewBinding(_ action: BuiltInQuickAction) -> Binding<Bool> {
        Binding(
            get: { store.settings.previewsResult(action) },
            set: { store.settings.setPreviewsResult($0, for: action) })
    }

    private func previewBinding(_ action: CustomQuickAction) -> Binding<Bool> {
        Binding(
            get: { action.previewsResult },
            set: { core.quickActionCoordinator.setPreviewsResult($0, id: action.id) })
    }

    private func launcherBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) })
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { store.settings.targetLanguage },
            set: { store.settings.targetLanguage = $0 })
    }

    private var modelChoices: [AIModelOption] {
        AIModelOption.availableGroups(
            settings: aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI
        )
        .flatMap(\.options)
    }

    private func repairInstalledModel() {
        // Catalog rows name a route without an effort; a repaired selection must carry the default.
        let options = modelChoices.map {
            AIModelOption.withDefaultEffort(
                $0.selection, settings: aiSettings, subscription: core.chatGPTSubscription,
                installedAI: core.installedAI)
        }
        var unavailable = Set<AIModelSource>()
        if !aiSettings.enabledInstalledProviders.contains(.codex)
            || core.chatGPTSubscription.phase == .signedOut
            || core.chatGPTSubscription.phase.isUnavailable
        {
            unavailable.insert(.codex)
        }
        for kind in InstalledAIKind.managedCLIKinds {
            let phase = core.installedAI.status(for: kind).phase
            guard
                !aiSettings.enabledInstalledProviders.contains(kind)
                    || phase == .signInRequired || phase == .notInstalled
            else { continue }
            unavailable.insert(kind.source)
        }
        store.repairInstalledModel(
            available: options, unavailableSources: unavailable,
            fallback: aiSettings.defaultModel)
    }

    private struct InstructionsEditorPanel: View {
        @Environment(\.settingsEditorDismiss) private var dismiss
        @State private var instructions: String
        @State private var model: AIModelSelection?

        let action: BuiltInQuickAction
        let builtIn: String
        let onSave: (String?, AIModelSelection?) -> Void

        init(
            action: BuiltInQuickAction, instructionOverride: String?,
            modelOverride: AIModelSelection?,
            onSave: @escaping (String?, AIModelSelection?) -> Void
        ) {
            self.action = action
            let builtIn = QuickActionPrompt.instructions(for: action)
            _instructions = State(initialValue: instructionOverride ?? builtIn)
            _model = State(initialValue: modelOverride)
            self.builtIn = builtIn
            self.onSave = onSave
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SettingsEditorHeader(
                    title: "Customize \(action.title)",
                    subtitle: "Tell Tinycast how you want \(action.title) to handle your selected text."
                )

                TextEditor(text: $instructions)
                    .font(.body)
                    .settingsEditorTextArea(height: Theme.Size.editorTextHeight * 2)

                QuickActionModelPicker(selection: $model)

                HStack(spacing: Theme.Spacing.md) {
                    Button("Use Default") { instructions = builtIn }
                        .buttonStyle(.modalAction(.standard, fillsWidth: false))
                        .disabled(instructions == builtIn)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.modalAction(.cancel))
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        onSave(instructions == builtIn ? nil : instructions, model)
                        dismiss()
                    }
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Theme.Spacing.dialogInset)
            .frame(width: Theme.Size.editorSheetWidth)
            .settingsEditorPanelSurface()
        }
    }
}
