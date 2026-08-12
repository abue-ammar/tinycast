import SwiftUI

/// Settings › Extensions › Advanced: where extensions are searched for, and what builds the ones that
/// arrive as source. Both are collapsed by default — the defaults are right for almost everyone.
struct ExtensionAdvancedSection: View {
    @Environment(AppCore.self) private var core
    @State private var expanded = false
    @State private var addingRegistry = false

    private var settings: AppSettings { core.settings }

    var body: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    packageManagerRow
                    Divider()
                    registryList
                }
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .sheet(isPresented: $addingRegistry) {
            RegistryEditor(
                onAdd: { registry in
                    settings.extensionRegistries.append(registry)
                    addingRegistry = false
                }, onCancel: { addingRegistry = false })
        }
    }

    // MARK: - Package manager

    private var packageManagerRow: some View {
        @Bindable var settings = core.settings
        return SettingsRow(
            title: "Package manager", subtitle: packageManagerSubtitle
        ) {
            Image(systemName: "shippingbox")
        } trailing: {
            Picker("", selection: $settings.extensionPackageManager) {
                ForEach(ExtensionPackageManager.allCases) { manager in
                    Text(manager.title).tag(manager)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var packageManagerSubtitle: String {
        let chosen = settings.extensionPackageManager
        guard let resolved = chosen.resolve() else {
            return chosen == .automatic
                ? "None found. Only registries that serve source need one."
                : "\(chosen.title) isn't installed. Only registries that serve source need one."
        }
        return chosen == .automatic
            ? "Using \(resolved.manager.title), at \(resolved.url.path)."
            : "At \(resolved.url.path)."
    }

    // MARK: - Registries

    private var registryList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Registries").font(Theme.Typography.sectionHeader).foregroundStyle(.secondary)
                Spacer()
                Button("Add…") { addingRegistry = true }
            }
            ForEach(settings.extensionRegistries) { registry in
                SettingsRow(title: registry.name, subtitle: registry.subtitle) {
                    Image(systemName: registry.kind == .raycastStore ? "bag" : "shippingbox.circle")
                        .foregroundStyle(.secondary)
                } trailing: {
                    Toggle("", isOn: binding(for: registry))
                        .labelsHidden()
                        .help(registry.isEnabled ? "Searched" : "Not searched")
                    if !registry.isBuiltIn {
                        Button {
                            settings.extensionRegistries.removeAll { $0.id == registry.id }
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(registry.name)")
                    }
                }
            }
            Text(
                "A registry is a source of code you will run. Add one only if you trust who "
                    + "publishes it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func binding(for registry: ExtensionRegistry) -> Binding<Bool> {
        Binding(
            get: { registry.isEnabled },
            set: { isOn in
                guard
                    let index = settings.extensionRegistries.firstIndex(where: {
                        $0.id == registry.id
                    })
                else { return }
                settings.extensionRegistries[index].isEnabled = isOn
            })
    }
}

/// Adds a GitHub registry from a URL, which is what someone has when they want one.
private struct RegistryEditor: View {
    let onAdd: (ExtensionRegistry) -> Void
    let onCancel: () -> Void

    @State private var url = ""
    @State private var name = ""

    private var parsed: ExtensionRegistry? {
        ExtensionRegistry.parse(url, name: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Add Registry").font(.title2.weight(.bold))
                Text(
                    "A GitHub repository holding one folder per extension, laid out like "
                        + "raycast/extensions."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                LabeledContent("Repository") {
                    TextField("owner/repo, or a link to the folder", text: $url)
                }
                LabeledContent("Name") {
                    TextField(parsed?.name ?? "Optional", text: $name)
                }
            }

            if let parsed {
                Text("Will search \(parsed.owner)/\(parsed.repository)/\(parsed.path) at \(parsed.ref).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !url.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("That doesn't look like a GitHub repository.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(
                "Extensions from a repository are source: installing one runs your package manager "
                    + "and the extension's own build script on this Mac."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let parsed else { return }
                    onAdd(parsed)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsed == nil)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
    }
}
