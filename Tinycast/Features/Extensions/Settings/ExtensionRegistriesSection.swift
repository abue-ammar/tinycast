import SwiftUI

/// Settings › Extensions: where extensions are searched for, and what builds the ones that arrive as
/// source. Plain sections rather than a collapsible — there are four rows, and hiding them behind a
/// disclosure only adds a thing to click.
struct ExtensionRegistriesSection: View {
    @Environment(AppCore.self) private var core
    @State private var addingRegistry = false

    private var settings: AppSettings { core.settings }

    var body: some View {
        Section {
            ForEach(settings.extensionRegistries) { registry in
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
            Button("Add Registry…") { addingRegistry = true }
        } header: {
            Text("Registries")
        } footer: {
            Text(
                "A registry is a source of code you will run. Add one only if you trust who "
                    + "publishes it."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $addingRegistry) {
            RegistryEditorSheet(
                onAdd: { registry in
                    settings.extensionRegistries.append(registry)
                    addingRegistry = false
                }, onCancel: { addingRegistry = false })
        }

        buildingSection
    }

    /// Only a source registry needs a package manager, and the one that ships is off by default — so
    /// the section says what it is for rather than sitting there as an unexplained dropdown.
    private var buildingSection: some View {
        @Bindable var settings = core.settings
        return Section {
            LabeledContent {
                Picker("", selection: $settings.extensionPackageManager) {
                    ForEach(ExtensionPackageManager.allCases) { manager in
                        Text(manager.title).tag(manager)
                    }
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                Text("Package manager")
                Text(packageManagerDetail)
            }
        } header: {
            Text("Building")
        } footer: {
            Text(
                "Extensions from a GitHub registry arrive as source, and are built when you install "
                    + "them — which starts by installing their dependencies. The Raycast Store serves "
                    + "extensions already built and never needs this."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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
private struct RegistryEditorSheet: View {
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
                TextField("owner/repo, or a link to the folder", text: $url)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Name").font(.callout.weight(.medium))
                TextField(parsed?.name ?? "Optional", text: $name)
                    .textFieldStyle(.roundedBorder)
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
