import Combine
import SwiftUI

/// A peer of the AI pane, not a section in it: it only borrows the provider layer.
struct QuickActionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var appSettings
    @Environment(QuickActionSettingsStore.self) private var store
    @Environment(AISettingsStore.self) private var aiSettings
    @Environment(VisibilityStore.self) private var visibility

    /// Polled like the Permissions pane: the grant lands in System Settings, which sends nothing.
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    @State private var editingAction: QuickAction?
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsRowTitle(.quickActionsQuickActions, "Enable Quick Actions")
                    Text(
                        "Act on the text you have selected in any app. Nothing is read until you "
                            + "press a shortcut.")
                }
                if appSettings.quickActionsEnabled, !isTrusted {
                    // Every shortcut fails without it; better said here than found one press later.
                    SettingsRow(
                        title: "Accessibility permission required",
                        subtitle: "Tinycast can't read your selection until it is granted."
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
        .sheet(item: $editingAction) { action in
            InstructionsEditorSheet(
                action: action,
                instructionOverride: store.settings.instructionOverride(for: action)
            ) { instructionOverride in
                store.settings.setInstructionOverride(instructionOverride, for: action)
            }
        }
        .onAppear {
            core.quickActionCoordinator.loadLanguages()
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
            ForEach(QuickAction.allCases) { action in
                SettingsRow(title: action.title, subtitle: subtitle(for: action)) {
                    Image(systemName: action.symbol)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    if !action.usesTranslationFramework {
                        Button {
                            editingAction = action
                        } label: {
                            SymbolImage(
                                name: "pencil", size: Theme.Size.quickActionHeaderIcon)
                        }
                        .buttonStyle(.plain)
                        .help("Edit \(action.title) instructions")
                        .accessibilityLabel("Edit \(action.title) instructions")
                    }
                    ShortcutRecorder(action: .command(CommandID(action)), isQuiet: true)
                    Picker("", selection: previewBinding(action)) {
                        Text("Replace").tag(false)
                        Text("Preview").tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(action.alwaysPreviews)
                    .accessibilityLabel("What \(action.title) does with its result")
                    if let entry = CommandCatalog.entry(for: CommandID(action)) {
                        Toggle("", isOn: launcherBinding(entry))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("Show \(action.title) in launcher")
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.quickActionsActions)
        } footer: {
            Text(
                "Replace puts the result straight into your document — undo in the app you were in "
                    + "brings it back. Preview shows it in a panel first. The checkbox lists the "
                    + "action in the launcher; its shortcut works either way."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        Section {
            AIModelSelectionRows(
                selection: store.model,
                select: store.select,
                modelLabel: {
                    SettingsRowTitle(.quickActionsModel, "Model")
                    Text("Used by every action except Translate.")
                },
                effortLabel: {
                    SettingsRowTitle(.quickActionsModel, "Reasoning effort")
                    Text("Applied when the selected model supports reasoning effort.")
                }
            )
        } header: {
            SettingsSectionHeader(.quickActionsModel)
        } footer: {
            Text(
                "Separate from chat's model on purpose: a shortcut you press all day should not "
                    + "bill an API every time. Apple Intelligence runs on this Mac for nothing."
            )
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
                Text("The panel can still translate into another language once it is open.")
            }
        } header: {
            SettingsSectionHeader(.quickActionsTranslate)
        } footer: {
            Text(
                "Translation uses Apple's own translator on this Mac, so it costs nothing and "
                    + "reaches no provider. A language downloads the first time you use it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for action: QuickAction) -> String? {
        action.alwaysPreviews ? "Always shown in a panel" : nil
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { appSettings.quickActionsEnabled },
            set: { core.quickActionCoordinator.setEnabled($0) })
    }

    private func previewBinding(_ action: QuickAction) -> Binding<Bool> {
        Binding(
            get: { store.settings.previewsResult(action) },
            set: { store.settings.setPreviewsResult($0, for: action) })
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
            installedAI: core.installedAI)
            .flatMap(\.options)
    }

    private func repairInstalledModel() {
        let options = modelChoices.map(\.selection)
        var unavailable = Set<AIModelSource>()
        if !aiSettings.enabledInstalledProviders.contains(.codex)
            || core.chatGPTSubscription.phase == .signedOut
            || core.chatGPTSubscription.phase.isUnavailable
        {
            unavailable.insert(.codex)
        }
        for kind in [InstalledAIKind.claude, .openCode] {
            guard aiSettings.enabledInstalledProviders.contains(kind)
            else {
                unavailable.insert(kind == .claude ? .claude : .openCode)
                continue
            }
            let phase = core.installedAI.status(for: kind).phase
            guard phase == .signInRequired || phase == .notInstalled else { continue }
            unavailable.insert(kind == .claude ? .claude : .openCode)
        }
        store.repairInstalledModel(
            available: options, unavailableSources: unavailable,
            fallback: aiSettings.defaultModel)
    }

    private struct InstructionsEditorSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State private var instructions: String

        let action: QuickAction
        let builtIn: String
        let onSave: (String?) -> Void

        init(
            action: QuickAction, instructionOverride: String?,
            onSave: @escaping (String?) -> Void
        ) {
            self.action = action
            let builtIn = QuickActionPrompt.instructions(for: action)
            _instructions = State(initialValue: instructionOverride ?? builtIn)
            self.builtIn = builtIn
            self.onSave = onSave
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Text("Customize \(action.title)")
                    .font(.title2.weight(.bold))

                Text("Tell Tinycast how you want \(action.title) to handle your selected text.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $instructions)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.sm)
                    .frame(height: Theme.Size.editorTextHeight * 2)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .fill(Theme.Colors.cardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                            .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                    )

                HStack {
                    Button("Use Default") { instructions = builtIn }
                        .disabled(instructions == builtIn)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        onSave(instructions == builtIn ? nil : instructions)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Theme.Spacing.xxl)
            .frame(width: Theme.Size.editorSheetWidth)
        }
    }
}
