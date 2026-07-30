import SwiftUI

struct AIChatSettingsView: View {
    @ObservedObject private var aiStore = AppCore.shared.aiStore
    @State private var apiKey: String = ""
    @State private var showingConsentSheet = false
    @State private var isEditingKey = false

    var body: some View {
        SettingsPane(
            title: "AI Chat",
            subtitle: "Configure AI assistant powered by Claude."
        ) {
            SettingsCard(header: "Provider") {
                SettingsRow(
                    title: "Enable AI Chat",
                    subtitle: consentSubtitle,
                    systemImage: "sparkles",
                    tint: .purple
                ) {
                    Toggle("", isOn: Binding(
                        get: { aiStore.isEnabled },
                        set: { newValue in
                            if newValue {
                                showingConsentSheet = true
                            } else {
                                aiStore.setEnabled(false)
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            if aiStore.isEnabled {
                SettingsCard(header: "Configuration") {
                    SettingsRow(
                        title: "API Key",
                        subtitle: apiKeySubtitle,
                        systemImage: "key.fill",
                        tint: .blue
                    ) {
                        if isEditingKey {
                            HStack(spacing: Theme.Spacing.sm) {
                                SecureField("Enter API key", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                                Button("Save") {
                                    if aiStore.saveAPIKey(apiKey) {
                                        isEditingKey = false
                                        apiKey = ""
                                    }
                                }
                                .controlSize(.small)
                                Button("Cancel") {
                                    isEditingKey = false
                                    apiKey = ""
                                }
                                .controlSize(.small)
                            }
                        } else {
                            HStack(spacing: Theme.Spacing.sm) {
                                if aiStore.loadAPIKey() != nil {
                                    Text("••••••••••••••••")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Not configured")
                                        .foregroundStyle(.secondary)
                                }
                                Button("Edit") {
                                    isEditingKey = true
                                    apiKey = aiStore.loadAPIKey() ?? ""
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Model",
                        subtitle: "The Claude model to use for conversations.",
                        systemImage: "brain",
                        tint: .indigo
                    ) {
                        Picker("", selection: $aiStore.selectedModel) {
                            ForEach(AIModel.allCases) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Clear History",
                        subtitle: "Delete all conversation messages from this device.",
                        systemImage: "trash",
                        tint: .red
                    ) {
                        Button("Clear…", role: .destructive) {
                            aiStore.clearHistory()
                        }
                        .controlSize(.small)
                        .disabled(aiStore.messages.isEmpty)
                    }
                }

                SettingsCard(header: "About") {
                    SettingsCallout(
                        text: """
                        AI Chat uses the Anthropic Claude API. Your conversations are sent to \
                        Anthropic's servers for processing. You need an API key from \
                        console.anthropic.com. Standard API rates apply.
                        """,
                        systemImage: "info.circle",
                        tint: .blue
                    )
                }
            }
        }
        .sheet(isPresented: $showingConsentSheet) {
            ConsentSheet(onAccept: {
                aiStore.setEnabled(true)
                showingConsentSheet = false
            }, onDecline: {
                showingConsentSheet = false
            })
        }
    }

    private var consentSubtitle: String {
        if aiStore.isEnabled {
            return "AI Chat is enabled. Your messages are sent to Anthropic for processing."
        } else {
            return "Enable AI Chat to start conversations with Claude. Requires an API key."
        }
    }

    private var apiKeySubtitle: String {
        if aiStore.loadAPIKey() == nil {
            return "Get your API key from console.anthropic.com"
        } else {
            return "Your API key is stored securely in the system keychain."
        }
    }
}

private struct ConsentSheet: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            VStack(spacing: Theme.Spacing.md) {
                Text("Enable AI Chat?")
                    .font(.title2.weight(.semibold))

                Text("""
                    AI Chat uses the Anthropic Claude API to power conversations.

                    • Your messages will be sent to Anthropic's servers
                    • You need an API key from console.anthropic.com
                    • Standard Anthropic API rates apply
                    • Conversation history is stored locally on your device
                    • You can disable this feature at any time

                    Learn more at anthropic.com
                    """)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400)
            }

            HStack(spacing: Theme.Spacing.md) {
                Button("Cancel") {
                    onDecline()
                }
                .keyboardShortcut(.cancelAction)

                Button("Enable AI Chat") {
                    onAccept()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 500)
    }
}
