import SwiftUI

struct AIModelSelectionRows<ModelLabel: View, EffortLabel: View>: View {
    @Environment(AISettingsStore.self) private var settings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

    let selection: AIModelSelection?
    let select: (AIModelSelection?) -> Void
    @ViewBuilder let modelLabel: () -> ModelLabel
    @ViewBuilder let effortLabel: () -> EffortLabel

    var body: some View {
        if modelGroups.isEmpty {
            Label("No AI provider configured", systemImage: "sparkles")
                .foregroundStyle(.secondary)
        } else {
            Picker(selection: modelBinding) {
                ForEach(modelGroups) { group in
                    Section(group.title) {
                        ForEach(group.options) { option in
                            Text(option.title).tag(Optional(option.selection))
                        }
                    }
                }
            } label: {
                modelLabel()
            }
            if !efforts.isEmpty {
                Picker(selection: effortBinding) {
                    ForEach(efforts) { effort in
                        Text(effort.title).tag(effort.id)
                    }
                } label: {
                    effortLabel()
                }
            }
        }
    }

    private var modelGroups: [AIModelOptionGroup] {
        AIModelOption.availableGroups(
            settings: settings, subscription: subscription, installedAI: installedAI)
    }

    private var efforts: [ChatGPTSubscription.Effort] {
        AIModelOption.efforts(
            for: selection, settings: settings, subscription: subscription,
            installedAI: installedAI)
    }

    private var modelBinding: Binding<AIModelSelection?> {
        Binding(
            get: { selection?.withEffort(nil) },
            set: { value in
                select(
                    value.map {
                        AIModelOption.withDefaultEffort(
                            $0, settings: settings, subscription: subscription,
                            installedAI: installedAI)
                    })
            })
    }

    private var effortBinding: Binding<String> {
        Binding(
            get: { selection?.effort ?? "" },
            set: { effort in
                guard let selection else { return }
                select(selection.withEffort(effort))
            })
    }
}
