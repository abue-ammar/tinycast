import SwiftUI

/// Provider config plus the preset library: one pane, gated behind the feature switch.
struct AITransformsSettingsView: View {
    @Environment(AITransformStore.self) private var store
    @Environment(AIProviderAccountStore.self) private var accounts
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    @State private var editor: EditorTarget?
    @State private var pendingDeletion: AITransform?
    @State private var editingAccount: AIProviderAccount?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            // 1. Canonical Tinycast Launcher Category (Aliases & Checkboxes)
            LauncherItemsSection(
                kind: .aiTransform,
                header: "AI Transforms",
                searchPrompt: "Search AI transforms…")

            // 2. General Preferences
            FeatureSwitchSection(
                header: "Preferences",
                enableTitle: "Enable AI transforms",
                enableSubtitle:
                    "Selected text is sent to the configured provider, and the result replaces it in place.",
                launcherSubtitle: "Show AI transforms in root search.",
                isEnabled: $settings.aiTransformsEnabled,
                showsInLauncher: $settings.aiTransformsShowInLauncher)

            Section {
                if !accounts.accounts.isEmpty {
                    Picker(selection: defaultAccountBinding) {
                        ForEach(accounts.accounts) { account in
                            Label {
                                Text(account.name)
                            } icon: {
                                if let icon = account.providerPreset?.iconName {
                                    Image(icon)
                                } else {
                                    Image(systemName: account.providerPreset?.symbolFallback ?? "sparkles")
                                }
                            }
                            .tag(account.id as UUID?)
                        }
                    } label: {
                        Text("Default Provider Account")
                        Text("Used when a transform does not specify its own provider.")
                    }
                }

                Picker(selection: $settings.aiExecutionMode) {
                    ForEach(AIExecutionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Text("Default Activation Mode")
                    Text(settings.aiExecutionMode.subtitle)
                }
            }
            .settingsEnabled(settings.aiTransformsEnabled)

            // 3. Configured Providers
            Section {
                if accounts.accounts.isEmpty {
                    Text("No provider accounts configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accounts.accounts) { account in
                        AIProviderAccountSettingsRow(
                            account: account,
                            isDefault: account.id == accounts.defaultAccountID,
                            onEdit: { editingAccount = account }
                        )
                    }
                }

                Button("Add Provider Account…") {
                    editingAccount = AIProviderAccount(
                        name: "",
                        providerPresetID: AIProvider.catalog.first?.id ?? AIProvider.customID,
                        baseURL: AIClient.defaultBaseURL,
                        defaultModel: AIClient.defaultModel
                    )
                }
            } header: {
                Text("Configured Providers")
            }
            .settingsEnabled(settings.aiTransformsEnabled)

            // 4. Transforms Library
            Section {
                if store.transforms.isEmpty {
                    Text("Add one to make it searchable from the launcher.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTransforms) { transform in
                        AITransformLibraryRow(
                            transform: transform,
                            accountName: accountName(for: transform),
                            onDuplicate: { duplicate(transform) },
                            onEdit: { editor = EditorTarget(transform: transform) },
                            onDelete: { pendingDeletion = transform }
                        )
                    }
                }

                Button("Add AI Transform…") { editor = EditorTarget(transform: nil) }
            } header: {
                Text("Transforms Library")
            }
            .settingsEnabled(settings.aiTransformsEnabled)
        }
        .formStyle(.grouped)
        .sheet(item: $editor) { target in
            AITransformEditorSheet(transform: target.transform)
        }
        .sheet(item: $editingAccount) { account in
            AIProviderAccountEditorSheet(
                account: account.name.isEmpty && !accounts.accounts.contains(where: { $0.id == account.id })
                    ? nil : account
            )
        }
        .alert(item: $pendingDeletion) { transform in
            Alert(
                title: Text("Delete “\(transform.name)”?"),
                message: Text("Its global shortcut and launcher references will also be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    core.aiTransformCoordinator.deleteTransform(id: transform.id)
                },
                secondaryButton: .cancel())
        }
    }

    private var defaultAccountBinding: Binding<UUID?> {
        Binding(
            get: { accounts.defaultAccountID },
            set: { newID in
                if let newID {
                    accounts.setDefault(id: newID)
                }
            }
        )
    }

    private func duplicate(_ transform: AITransform) {
        try? store.duplicate(id: transform.id)
    }

    private func accountName(for transform: AITransform) -> String {
        if let id = transform.providerAccountID, let account = accounts.account(id: id) {
            return account.name
        }
        return accounts.defaultAccount?.name ?? "Default"
    }

    private var sortedTransforms: [AITransform] {
        store.transforms.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

private struct EditorTarget: Identifiable {
    let id = UUID()
    let transform: AITransform?
}

/// A row in the Configured Providers section.
private struct AIProviderAccountSettingsRow: View {
    let account: AIProviderAccount
    let isDefault: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let iconName = account.providerPreset?.iconName {
                Image(iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: account.providerPreset?.symbolFallback ?? "sparkles")
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(account.name)
                        .font(.body.weight(.medium))
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, Theme.Spacing.xs)
                            .padding(.vertical, 1)
                            .background(Theme.Colors.controlSurface, in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit Provider Account")
        }
        .padding(.vertical, 2)
    }

    private var subtitleText: String {
        var parts: [String] = []
        parts.append(account.baseURL)
        if !account.defaultModel.isEmpty {
            parts.append("Model: \(account.defaultModel)")
        }
        if account.defaultReasoning != .none {
            parts.append("Reasoning: \(account.defaultReasoning.title)")
        }
        return parts.joined(separator: " • ")
    }
}

/// A row in the Transforms Library section.
private struct AITransformLibraryRow: View {
    let transform: AITransform
    let accountName: String
    let onDuplicate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: AITransform.sfSymbol)
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.Colors.textPrimary)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(transform.name)
                    .font(.body.weight(.medium))
                Text(transform.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(metaBadgeText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.xs) {
                Button(action: onDuplicate) {
                    Image(systemName: "doc.on.doc")
                        .font(.body)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Duplicate as Copy of…")

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.body)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit Transform")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete Transform")
            }
        }
        .padding(.vertical, 2)
    }

    private var metaBadgeText: String {
        var parts: [String] = []
        let mode = transform.activationMode?.title ?? "Inherit Mode"
        parts.append(mode)
        parts.append(accountName)
        if let model = transform.model, !model.isEmpty {
            parts.append(model)
        }
        if let reasoning = transform.reasoningEffort, reasoning != .none {
            parts.append("Reasoning: \(reasoning.title)")
        }
        return parts.joined(separator: " • ")
    }
}
