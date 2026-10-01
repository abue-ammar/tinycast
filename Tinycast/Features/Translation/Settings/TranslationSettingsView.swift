import SwiftUI

struct TranslationSettingsView: View {
    @Environment(TranslationCoordinator.self) private var coordinator

    /// Only ever the user's own typing: a saved key is never read back into the field.
    @State private var keyDraft = ""
    @State private var providersPresented = false

    private static let keyFieldWidth: CGFloat = 160

    var body: some View {
        Form {
            translationSection
            providersSection
            FeatureCommandsSection(owner: .translation, anchor: .translationCommands)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.translation)
        .settingsEditorPanel(isPresented: $providersPresented) {
            AIProvidersPanel(onDone: { providersPresented = false })
        }
        .onAppear { coordinator.prepareSettings() }
    }

    // MARK: - Translation

    private var translationSection: some View {
        Section {
            Picker(selection: providerBinding) {
                ForEach(TranslationProvider.allCases, id: \.self) { provider in
                    Text(provider.title).tag(provider)
                }
            } label: {
                SettingsRowTitle(.translationTranslation, "Service")
            }
            Picker(selection: sourceBinding) {
                Text("Detect Language").tag(Self.autoSource)
                Divider()
                ForEach(coordinator.sourceLanguages) { language in
                    Text(language.name).tag(language.id)
                }
                if let unlisted = unlistedSource {
                    Text(coordinator.sourceLabel).tag(unlisted)
                }
            } label: {
                SettingsRowTitle(.translationTranslation, "Source Language")
            }
            .settingsEnabled(languagesAvailable)
            Picker(selection: targetBinding) {
                ForEach(coordinator.targetLanguages) { language in
                    Text(language.name).tag(language.id)
                }
                if let unlisted = unlistedTarget {
                    Text(coordinator.targetLabel).tag(unlisted)
                }
            } label: {
                SettingsRowTitle(.translationTranslation, "Target Language")
            }
            .settingsEnabled(languagesAvailable)
            statusRow
        } header: {
            SettingsSectionHeader(.translationTranslation)
        } footer: {
            Text(
                "Text is sent to the selected service after you stop typing for 0.6 seconds. "
                    + "No translation history is kept. Copies follow your clipboard settings."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Whatever stands between the current configuration and a translation, or nothing.
    @ViewBuilder private var statusRow: some View {
        if coordinator.isLoadingLanguages {
            HStack(spacing: Theme.Spacing.lg) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Theme.Size.settingsRowIcon)
                Text("Loading DeepL languages…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = coordinator.languageError {
            noticeRow(error) {
                Button("Retry") { coordinator.retry() }
                    .disabled(!coordinator.canRetry)
            }
        } else if let issue = coordinator.configurationIssue {
            noticeRow(issue) { EmptyView() }
        }
    }

    private func noticeRow<Trailing: View>(
        _ message: String, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .frame(width: Theme.Size.settingsRowIcon)
            Text(message)
                .foregroundStyle(.orange)
            Spacer(minLength: Theme.Spacing.lg)
            trailing()
        }
    }

    // MARK: - Providers

    private var providersSection: some View {
        Section {
            modelRow
            if !coordinator.efforts.isEmpty { effortRow }
            SettingsRow(title: "API Connections", subtitle: "Shared with AI Chat and Quick Actions.") {
                Button("Manage AI Providers…") { providersPresented = true }
            }
            Picker(selection: planBinding) {
                ForEach(DeepLPlan.allCases, id: \.self) { plan in
                    Text("DeepL API \(plan.title)").tag(plan)
                }
            } label: {
                SettingsRowTitle(.translationProviders, "Account Type")
            }
            SettingsRow(
                title: "API Key", subtitle: "Stored in Keychain for the selected account.",
                anchor: .translationProviders
            ) {
                RevealableSecureField(
                    title: "DeepL API Key", text: $keyDraft, prompt: Text(keyPrompt)
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: Self.keyFieldWidth)
                Button("Save Key", action: saveKey)
                    .disabled(!hasKeyDraft)
                Button("Remove Key") { coordinator.removeDeepLKey() }
                    .disabled(!coordinator.hasDeepLKey)
                    .accessibilityLabel("Remove DeepL API Key")
            }
        } header: {
            SettingsSectionHeader(.translationProviders)
        }
    }

    private var modelRow: some View {
        Picker(selection: modelBinding) {
            Text("None").tag(AIModelSelection?.none)
            Divider()
            ForEach(coordinator.modelGroups) { group in
                Section(group.title) {
                    ForEach(group.options) { option in
                        Text(option.title).tag(Optional(option.selection))
                    }
                }
            }
            if let unlisted = unlistedModel {
                Text("\(unlisted.model) (unavailable)").tag(Optional(unlisted))
            }
        } label: {
            SettingsRowTitle(.translationProviders, "AI Model")
            if coordinator.modelGroups.isEmpty {
                Text("Add an API connection below.")
            }
        }
    }

    private var effortRow: some View {
        Picker(selection: effortBinding) {
            Text("Default").tag("")
            Divider()
            ForEach(coordinator.efforts) { effort in
                Text(effort.title).tag(effort.id)
            }
        } label: {
            SettingsRowTitle(.translationProviders, "Reasoning Effort")
        }
    }

    // MARK: - State

    private static let autoSource = "auto"

    private var languagesAvailable: Bool { !coordinator.targetLanguages.isEmpty }

    private var hasKeyDraft: Bool {
        !keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var keyPrompt: String { coordinator.hasDeepLKey ? "Saved" : "Not configured" }

    /// The catalog's own spelling of the saved code, so a DeepL `EN` and a saved `en` select as one.
    private func listedCode(_ code: String, in languages: [TranslationLanguage]) -> String {
        languages.first { TranslationLanguages.matches($0.id, code) }?.id ?? code
    }

    private var selectedSource: String {
        let code = coordinator.settings.sourceLanguage
        guard !TranslationLanguages.matches(code, Self.autoSource) else { return Self.autoSource }
        return listedCode(code, in: coordinator.sourceLanguages)
    }

    private var selectedTarget: String {
        listedCode(coordinator.settings.targetLanguage, in: coordinator.targetLanguages)
    }

    /// A saved language the current catalog does not list still shows as what it is.
    private var unlistedSource: String? {
        let code = selectedSource
        guard code != Self.autoSource, !coordinator.sourceLanguages.contains(where: { $0.id == code })
        else { return nil }
        return code
    }

    private var unlistedTarget: String? {
        let code = selectedTarget
        return coordinator.targetLanguages.contains { $0.id == code } ? nil : code
    }

    /// The saved route once its connection or model has gone, so the picker can still name it.
    private var unlistedModel: AIModelSelection? {
        guard let model = coordinator.settings.model?.withEffort(nil),
            !coordinator.modelGroups.contains(where: { group in
                group.options.contains { $0.selection == model }
            })
        else { return nil }
        return model
    }

    // MARK: - Bindings

    private var providerBinding: Binding<TranslationProvider> {
        Binding(
            get: { coordinator.settings.provider },
            set: { coordinator.selectProvider($0) })
    }

    private var sourceBinding: Binding<String> {
        Binding(
            get: { selectedSource },
            set: { coordinator.setSourceLanguage($0) })
    }

    private var targetBinding: Binding<String> {
        Binding(
            get: { selectedTarget },
            set: { coordinator.setTargetLanguage($0) })
    }

    private var planBinding: Binding<DeepLPlan> {
        Binding(
            get: { coordinator.settings.deepLPlan },
            set: { coordinator.setDeepLPlan($0) })
    }

    /// Re-picking the current model hands back the saved selection, so its effort survives.
    private var modelBinding: Binding<AIModelSelection?> {
        Binding(
            get: { coordinator.settings.model?.withEffort(nil) },
            set: { picked in
                let current = coordinator.settings.model
                coordinator.selectModel(picked == current?.withEffort(nil) ? current : picked)
            })
    }

    private var effortBinding: Binding<String> {
        Binding(
            get: { coordinator.settings.model?.effort ?? "" },
            set: { effort in
                guard let model = coordinator.settings.model else { return }
                coordinator.selectModel(model.withEffort(effort.isEmpty ? nil : effort))
            })
    }

    private func saveKey() {
        if coordinator.saveDeepLKey(keyDraft) { keyDraft = "" }
    }
}
