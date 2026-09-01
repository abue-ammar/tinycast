import SwiftUI

/// The small library editor for named, reusable action sequences.
struct ActionChainsSettingsView: View {
    @Environment(ActionChainStore.self) private var store
    @Environment(AppCore.self) private var core
    @State private var editor: ActionChainEditorTarget?
    @State private var pendingDeletion: ActionChain?

    var body: some View {
        Form {
            Section {
                if store.chains.isEmpty {
                    Text("Add a chain to run several existing actions from one launcher row or shortcut.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.chains) { chain in
                        ActionChainSettingsRow(
                            chain: chain,
                            onEdit: { editor = ActionChainEditorTarget(chain: chain) },
                            onDelete: { pendingDeletion = chain })
                    }
                }
                Button("Add Action Chain…") { editor = ActionChainEditorTarget(chain: nil) }
            } header: {
                Text("Action Chains")
            } footer: {
                Text("Steps run in order. A missing or ineligible step stops the chain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editor) { target in ActionChainEditorSheet(chain: target.chain) }
        .alert(item: $pendingDeletion) { chain in
            Alert(
                title: Text("Delete “\(chain.name)”?"),
                message: Text("Its global shortcut and launcher references will also be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    core.actionChainCoordinator.deleteActionChain(id: chain.id)
                },
                secondaryButton: .cancel())
        }
    }
}

private struct ActionChainEditorTarget: Identifiable {
    let id = UUID()
    let chain: ActionChain?
}

private struct ActionChainSettingsRow: View {
    let chain: ActionChain
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: chain.name, subtitle: "\(chain.steps.count) actions") {
            Image(systemName: ActionChain.sfSymbol)
        } trailing: {
            ShortcutRecorder(action: .actionChain(id: chain.id))
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(chain.name)")
            Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(.red) }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(chain.name)")
        }
    }
}

private struct ActionChainEditorSheet: View {
    @Environment(AppCore.self) private var core
    @Environment(ActionChainStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let chain: ActionChain?
    @State private var name = ""
    @State private var steps: [ActionChainStep] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text(chain == nil ? "Add Action Chain" : "Edit Action Chain")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $name)
            List {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        Text(step.label(apps: applications, commands: commands, quicklinks: quicklinks))
                        Spacer()
                        Button {
                            steps.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(minHeight: 140)
            Menu("Add Action") {
                Menu("Application") {
                    ForEach(applications) { app in
                        Button(app.name) { steps.append(.application(bundleID: app.bundleID!)) }
                    }
                }
                Menu("System Action") {
                    ForEach(SystemAction.ID.allCases, id: \.self) { id in
                        let action = SystemActionCatalog.action(id: id)
                        if case .none = action.confirmation {
                            Button(action.name) { steps.append(.systemAction(id: id.rawValue)) }
                        }
                    }
                }
                Menu("Window Command") {
                    ForEach(WindowCommand.ID.allCases, id: \.self) { id in
                        if SpaceDirection(id) == nil {
                            Button(WindowCommandCatalog.command(id: id)?.name ?? id.rawValue) {
                                steps.append(.windowCommand(id: id.rawValue))
                            }
                        }
                    }
                }
                Menu("Custom Command") {
                    ForEach(
                        commands.filter {
                            $0.isEnabled && $0.arguments.isEmpty && !$0.requiresConfirmation
                        }
                    ) { command in
                        Button(command.name) { steps.append(.customCommand(id: command.id)) }
                    }
                }
                Menu("Quicklink") {
                    ForEach(
                        quicklinks.filter {
                            $0.isEnabled && !QuicklinkDestination.containsPlaceholder($0.link)
                        }
                    ) { quicklink in
                        Button(quicklink.name) { steps.append(.quicklink(id: quicklink.id)) }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save", action: save).buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460)
        .onAppear {
            name = chain?.name ?? ""
            steps = chain?.steps ?? []
        }
    }

    private var applications: [AppEntry] {
        core.appIndex.apps.filter { $0.kind == .application && $0.bundleID != nil }
    }

    private var commands: [CustomCommand] { core.customCommands.commands }
    private var quicklinks: [Quicklink] { core.quicklinks.quicklinks }

    private func save() {
        do {
            let value = ActionChain(id: chain?.id ?? UUID(), name: name, steps: steps)
            if chain == nil {
                _ = try core.actionChainCoordinator.addActionChain(value)
            } else {
                try core.actionChainCoordinator.updateActionChain(value)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private extension ActionChainStep {
    func label(apps: [AppEntry], commands: [CustomCommand], quicklinks: [Quicklink]) -> String {
        switch self {
        case .application(let bundleID):
            return apps.first { $0.bundleID == bundleID }?.name ?? "Missing application"
        case .systemAction(let id):
            return SystemAction.ID(rawValue: id).map { SystemActionCatalog.action(id: $0).name }
                ?? "Missing system action"
        case .windowCommand(let id):
            return WindowCommand.ID(rawValue: id).flatMap { WindowCommandCatalog.command(id: $0)?.name }
                ?? "Missing window command"
        case .customCommand(let id): return commands.first { $0.id == id }?.name ?? "Missing custom command"
        case .quicklink(let id): return quicklinks.first { $0.id == id }?.name ?? "Missing quicklink"
        }
    }
}
