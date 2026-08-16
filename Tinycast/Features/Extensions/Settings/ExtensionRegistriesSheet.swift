import SwiftUI

/// Where searching looks, and what builds what it finds.
///
/// A sheet reached from search — from the Install row's "Registries…" and from inside the search
/// sheet itself — rather than a row of its own in the pane. A registry is not a fourth way to install
/// something; it is the setting that decides what searching can find, and it belongs where that
/// question is asked.
struct ExtensionRegistriesSheet: View {
    let onClose: () -> Void

    @Environment(AppCore.self) private var core
    @State private var addingRegistry = false

    private var settings: AppSettings { core.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Registries").font(.title2.weight(.bold))
                Text("Where Tinycast looks when you search for an extension to install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.xxl)

            Form {
                // Two sections, because the two kinds are not variants of one thing: the store is a
                // fixed, prebuilt source you can only switch on or off, and a GitHub registry is
                // something you add, that serves source, and that has to be built to run.
                Section {
                    ForEach(storeRegistries) { registry in
                        registryRow(registry)
                    }
                } header: {
                    Text("Raycast Store")
                } footer: {
                    Text(
                        "Prebuilt extensions, through the endpoint the store's own site searches. "
                            + "Not an official API, so a GitHub registry is the fallback if it changes."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    if gitHubRegistries.isEmpty {
                        Text("None yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(gitHubRegistries) { registry in
                            registryRow(registry)
                        }
                    }
                    Button("Add Registry…") { addingRegistry = true }
                    // This section's business and nothing else's: only a GitHub registry serves
                    // source, and only source has to be built.
                    if !gitHubRegistries.isEmpty {
                        buildingRow
                    }
                } header: {
                    Text("GitHub Registries")
                } footer: {
                    Text(
                        "A repository with one folder per extension, laid out like "
                            + "raycast/extensions. These serve source, so installing one builds it "
                            + "here — dependencies first, with the package manager above. Add a "
                            + "registry only if you trust who publishes it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Spacing.xxl)
        }
        .frame(width: Theme.Size.editorSheetWidth, height: 560)
        .sheet(isPresented: $addingRegistry) {
            RegistryEditorSheet(
                onAdd: { registry in
                    settings.extensionRegistries.append(registry)
                    addingRegistry = false
                }, onCancel: { addingRegistry = false })
        }
    }

    private var storeRegistries: [ExtensionRegistry] {
        settings.extensionRegistries.filter { $0.kind == .raycastStore }
    }

    private var gitHubRegistries: [ExtensionRegistry] {
        settings.extensionRegistries.filter { $0.kind == .github }
    }

    private func registryRow(_ registry: ExtensionRegistry) -> some View {
        SettingsRow(title: registry.name, subtitle: registry.subtitle) {
            registryIcon(registry)
        } trailing: {
            Toggle("", isOn: binding(for: registry))
                .labelsHidden()
                .help(registry.isEnabled ? "Searched" : "Not searched")
            if !registry.isBuiltIn {
                Button {
                    settings.extensionRegistries.removeAll { $0.id == registry.id }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Remove Registry")
                .accessibilityLabel("Remove \(registry.name)")
            }
        }
    }

    private var buildingRow: some View {
        @Bindable var settings = core.settings
        return SettingsRow(title: "Package manager", subtitle: packageManagerDetail) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
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

    private var packageManagerDetail: String {
        let chosen = settings.extensionPackageManager
        guard let resolved = chosen.resolve() else {
            return chosen == .automatic
                ? "None found on this Mac. Install pnpm, npm, Yarn or Bun to use a source registry."
                : "\(chosen.title) isn't installed on this Mac."
        }
        return chosen == .automatic
            ? "Found \(resolved.manager.title) at \(resolved.url.path)."
            : "Found at \(resolved.url.path)."
    }

    @ViewBuilder
    private func registryIcon(_ registry: ExtensionRegistry) -> some View {
        switch registry.kind {
        case .raycastStore:
            Image(systemName: "bag")
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.settingsRowIcon)
        case .github:
            // The same mark the About window uses, as a template so it reads as an icon.
            Image("BrandGitHub")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
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
struct RegistryEditorSheet: View {
    let onAdd: (ExtensionRegistry) -> Void
    let onCancel: () -> Void

    @State private var url = ""
    @State private var name = ""

    private var parsed: ExtensionRegistry? { ExtensionRegistry.parse(url, name: name) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Add Registry").font(.title2.weight(.bold))
                Text(
                    "A GitHub repository holding one folder per extension, laid out like "
                        + "raycast/extensions."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Repository").font(.callout.weight(.medium))
                TextField("", text: $url, prompt: Text("owner/repo, or a link to the folder"))
                    .textFieldStyle(.roundedBorder)
                    .pointerStyle(.horizontalText)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name").font(.callout.weight(.medium))
                TextField("", text: $name, prompt: Text(parsed?.name ?? "Optional"))
                    .textFieldStyle(.roundedBorder)
                    .pointerStyle(.horizontalText)
            }

            if let parsed {
                Text(
                    "Will search \(parsed.owner)/\(parsed.repository)/\(parsed.path) at \(parsed.ref)."
                )
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
