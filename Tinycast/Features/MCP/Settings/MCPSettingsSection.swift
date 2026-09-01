import SwiftUI

/// Settings → AI's MCP half: the switch, the servers, and what each one is doing right now.
struct MCPSettingsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var appSettings
    @Environment(MCPSettingsStore.self) private var store
    @State private var editor: MCPServerEditorTarget?
    @State private var pendingRemoval: MCPServer?

    var body: some View {
        @Bindable var appSettings = appSettings
        Section {
            Toggle("Enable MCP servers", isOn: $appSettings.mcpEnabled)
            Group {
                if store.servers.isEmpty {
                    Text("No MCP servers yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.servers) { server in
                        MCPServerRow(
                            server: server, status: core.mcp.status(of: server.id),
                            onEdit: { editor = MCPServerEditorTarget(server: server, isNew: false) },
                            onRemove: { pendingRemoval = server })
                    }
                }
                Button("Add MCP Server…", systemImage: "plus") {
                    editor = MCPServerEditorTarget(server: MCPServer(), isNew: true)
                }
            }
            .settingsEnabled(appSettings.mcpEnabled)
        } header: {
            Text("MCP Servers")
        } footer: {
            Text(
                "Tools from every enabled server are offered to the model; type @slug to address "
                    + "one directly. The first call of a chat asks before it runs. Credentials "
                    + "stay in your login Keychain."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .sheet(item: $editor) { target in
            MCPServerEditor(target: target, onSave: save, onCancel: { editor = nil })
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.title ?? "this server")?", isPresented: removalBinding,
            presenting: pendingRemoval
        ) { server in
            Button("Remove", role: .destructive) { remove(server) }
        } message: { _ in
            Text("Its tools stop being offered, and its stored credentials are deleted.")
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    /// A returned message is shown in the sheet; nil closes it.
    private func save(_ server: MCPServer, _ secrets: MCPSecretStore.Secrets) -> String? {
        do {
            try MCPSecretStore().save(secrets, for: server.id)
        } catch {
            return "The credentials could not be saved to your login Keychain."
        }
        store.save(server)
        editor = nil
        core.mcpCoordinator.applyEnabled()
        return nil
    }

    private func remove(_ server: MCPServer) {
        try? MCPSecretStore().remove(for: server.id)
        store.remove(id: server.id)
        pendingRemoval = nil
        core.mcpCoordinator.applyEnabled()
    }
}

private struct MCPServerRow: View {
    let server: MCPServer
    let status: MCPServerStatus
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        SettingsRow(title: server.title, subtitle: subtitle) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(server.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        } trailing: {
            Button(action: onEdit) { Image(systemName: "pencil") }
                .buttonStyle(.plain)
                .help("Edit \(server.title)")
                .accessibilityLabel("Edit \(server.title)")
            Button(action: onRemove) {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove \(server.title)")
            .accessibilityLabel("Remove \(server.title)")
        }
    }

    /// The slug leads, because it is the half a reader has to type into the composer.
    private var subtitle: String {
        let state = server.isEnabled ? status.label : "Disabled"
        return "@\(server.slug) · \(state) · \(server.transport.summary)"
    }
}
