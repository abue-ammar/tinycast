import SwiftUI

/// The quicklink library plus the behaviour that applies to all of them.
struct QuicklinksSettingsView: View {
    @Environment(QuicklinkStore.self) private var store
    @Environment(QuicklinkCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .quicklinksQuicklinks,
                enableTitle: "Enable quicklinks",
                enableSubtitle: "Open saved links and searches from the launcher.",
                isEnabled: $settings.quicklinksEnabled,
                showsInLauncher: $settings.quicklinksShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            Group {
                if !store.isAvailable { storageNotice }
                FeatureCommandsSection(owner: .quicklinks, anchor: .quicklinksCommands)
                library
                behaviour
                transfer
            }
            .settingsEnabled(settings.quicklinksEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.quicklinks)
    }

    // MARK: - Sections

    private var storageNotice: some View {
        Section {
            Label(
                "Changes can't be saved: the database couldn't be opened. Its file is untouched.",
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
                        ? "No quicklinks yet."
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
                                coordinator.setQuicklinkEnabled($0, id: quicklink.id)
                            }),
                        onEdit: { coordinator.editQuicklink(quicklink) },
                        onDelete: {
                            Task { await coordinator.deleteQuicklink(id: quicklink.id, alwaysConfirm: true) }
                        })
                }
            }
            Button {
                coordinator.editQuicklink(nil)
            } label: {
                SettingsRowTitle(.quicklinksQuicklinks, "Add Quicklink")
            }
        }
    }

    private var behaviour: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.quicklinkOpensNewWindow) {
                SettingsRowTitle(.quicklinksBehaviour, "Open in a new window")
                Text("Where the app supports it.")
            }
            Picker(selection: $settings.quicklinkSelectionFallback) {
                ForEach(QuicklinkSelectionFallback.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                SettingsRowTitle(.quicklinksBehaviour, "When there's no selected text")
                Text("For links that use {selection}.")
            }
            Toggle(isOn: $settings.quicklinkConfirmsBeforeDelete) {
                SettingsRowTitle(.quicklinksBehaviour, "Confirm before deleting")
                Text("From the launcher's Actions menu.")
            }
        } header: {
            SettingsSectionHeader(.quicklinksBehaviour)
        }
    }

    private var transfer: some View {
        Section {
            LabeledContent {
                Button("Import…") { Task { await coordinator.importQuicklinks() } }
            } label: {
                SettingsRowTitle(.quicklinksImportExport, "Import quicklinks")
                Text("From a JSON file; duplicates are skipped.")
            }
            LabeledContent {
                Button("Export…") { Task { await coordinator.exportQuicklinks() } }
                    .disabled(store.quicklinks.isEmpty)
            } label: {
                SettingsRowTitle(.quicklinksImportExport, "Export quicklinks")
                Text("To a JSON file.")
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
            SymbolImage(
                name: quicklink.symbol,
                size: Theme.Size.settingsRowIcon - Theme.Spacing.xs
            )
            .frame(width: SettingsListMetrics.iconSize, height: SettingsListMetrics.iconSize)
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
}
