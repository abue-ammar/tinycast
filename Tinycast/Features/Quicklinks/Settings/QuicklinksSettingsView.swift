import SwiftUI

/// The quicklink library plus the behaviour that applies to all of them.
struct QuicklinksSettingsView: View {
    @Environment(QuicklinkStore.self) private var store
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var query = ""
    @State private var pendingDeletion: Quicklink?

    var body: some View {
        @Bindable var core = core
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .quicklinksQuicklinks,
                enableTitle: "Enable quicklinks",
                enableSubtitle:
                    "Open saved destinations from the launcher, a shortcut, or Search Quicklinks.",
                launcherSubtitle: "Find your quicklinks in launcher search.",
                isEnabled: $settings.quicklinksEnabled,
                showsInLauncher: $settings.quicklinksShowInLauncher)

            Group {
                if !store.isAvailable { storageNotice }
                library
                behaviour
                transfer
            }
            .settingsEnabled(settings.quicklinksEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.quicklinks)
        // Presented from the pane, so "Create Quicklink" can open it from the palette.
        .sheet(item: $core.pendingQuicklinkEdit) { request in
            QuicklinkEditorSheet(quicklink: request.quicklink)
        }
        .alert(item: $pendingDeletion) { quicklink in
            Alert(
                title: Text("Delete “\(quicklink.name)”?"),
                message: Text("Its global shortcut and launcher references will also be removed."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await core.quicklinkCoordinator.deleteQuicklink(id: quicklink.id, confirming: false)
                    }
                },
                secondaryButton: .cancel())
        }
    }

    // MARK: - Sections

    private var storageNotice: some View {
        Section {
            Label(
                "Quicklinks can't be saved: the database couldn't be opened, so nothing you change"
                    + " here will stick. The existing file was left untouched.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var library: some View {
        Section {
            if !store.quicklinks.isEmpty {
                SettingsFilterField(prompt: "Search quicklinks…", query: $query)
            }
            if results.isEmpty {
                Text(
                    store.quicklinks.isEmpty
                        ? "Add one to make it searchable from the launcher."
                        : "No quicklink matches “\(query)”."
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(results) { quicklink in
                    QuicklinkSettingsRow(
                        quicklink: quicklink,
                        isEnabled: Binding(
                            get: { quicklink.isEnabled },
                            set: {
                                core.quicklinkCoordinator.setQuicklinkEnabled($0, id: quicklink.id)
                            }),
                        onEdit: { core.quicklinkCoordinator.editQuicklink(quicklink) },
                        onDelete: { pendingDeletion = quicklink })
                }
            }
            Button {
                core.quicklinkCoordinator.editQuicklink(nil)
            } label: {
                SettingsRowTitle(.quicklinksQuicklinks, "Add Quicklink")
            }
        } footer: {
            Text("Name it, paste a link, then add an alias or a shortcut if you want one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var behaviour: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.quicklinkOpensNewWindow) {
                SettingsRowTitle(.quicklinksBehaviour, "Open in a new window")
                Text(
                    "Ask the handler for a new window instead of reusing its frontmost tab. "
                        + "Only apps that accept a new-window argument can honour this.")
            }
            Picker(selection: $settings.quicklinkSelectionFallback) {
                ForEach(QuicklinkSelectionFallback.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                SettingsRowTitle(.quicklinksBehaviour, "When there's no selected text")
                Text("What {selection} does when the app in front exposes nothing to read.")
            }
            Toggle(isOn: $settings.quicklinkConfirmsBeforeDelete) {
                SettingsRowTitle(.quicklinksBehaviour, "Confirm before deleting")
                Text("Ask first when deleting a quicklink from the launcher's Actions menu.")
            }
        } header: {
            SettingsSectionHeader(.quicklinksBehaviour)
        }
    }

    private var transfer: some View {
        Section {
            LabeledContent {
                Button("Import…") { Task { await core.quicklinkCoordinator.importQuicklinks() } }
            } label: {
                SettingsRowTitle(.quicklinksImportExport, "Import quicklinks")
                Text("Add quicklinks from a JSON file, skipping any you already have.")
            }
            LabeledContent {
                Button("Export…") { Task { await core.quicklinkCoordinator.exportQuicklinks() } }
                    .disabled(store.quicklinks.isEmpty)
            } label: {
                SettingsRowTitle(.quicklinksImportExport, "Export quicklinks")
                Text("Write your whole library to a JSON file.")
            }
        } header: {
            SettingsSectionHeader(.quicklinksImportExport)
        }
    }

    /// The store already publishes display order, so filtering keeps pins at the top.
    private var results: [Quicklink] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.quicklinks }
        return store.quicklinks.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.link.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

private struct QuicklinkSettingsRow: View {
    let quicklink: Quicklink
    @Binding var isEnabled: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsRow(title: quicklink.name, subtitle: quicklink.link) {
            SymbolImage(name: symbol, size: 13)
        } trailing: {
            if quicklink.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
                    .help("Pinned to the top")
            }
            if !quicklink.showsInRootSearch {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .help("Hidden from root search")
            }

            // An alias only reaches the ranker through the root-search slice, so it dims with it.
            AliasField(key: quicklink.entryID, name: quicklink.name)
                .settingsEnabled(quicklink.isEnabled && quicklink.showsInRootSearch)

            // A disabled quicklink's shortcut fires into the funnel's refusal, so it dims too.
            ShortcutRecorder(action: .quicklink(id: quicklink.id))
                .settingsEnabled(quicklink.isEnabled)

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit Quicklink")
            .accessibilityLabel("Edit \(quicklink.name)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete Quicklink")
            .accessibilityLabel("Delete \(quicklink.name)")

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Enabled")
                .accessibilityLabel("Enable \(quicklink.name)")
        }
    }

    private var symbol: String {
        quicklink.iconSymbol ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol
            ?? Quicklink.sfSymbol
    }
}
