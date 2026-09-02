import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var confirmingClear = false
    @State private var showingAppPicker = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                SettingsRow(title: "Clipboard History", anchor: .clipboardGlobalShortcuts) {
                    ShortcutRecorder(action: .command(.clipboardHistory))
                }
            } header: {
                SettingsSectionHeader(.clipboardGlobalShortcuts)
            } footer: {
                Text("Open the clipboard history browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(selection: $settings.clipboardRetention) {
                    ForEach(ClipboardRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                } label: {
                    SettingsRowTitle(.clipboardHistory, "Keep history for")
                    Text("Entries older than this are deleted automatically.")
                }
                .onChange(of: settings.clipboardRetention) {
                    core.clipboardCoordinator.applyRetention(settings.clipboardRetention)
                }
            } header: {
                SettingsSectionHeader(.clipboardHistory)
            }

            Section {
                ForEach(settings.clipboardDisabledApps, id: \.self) { bundleID in
                    DisabledAppRow(bundleID: bundleID) {
                        settings.clipboardDisabledApps.removeAll { $0 == bundleID }
                    }
                }

                Button("Add Application…") { showingAppPicker = true }
                    .popover(isPresented: $showingAppPicker, arrowEdge: .bottom) {
                        AppPickerPopover(excluded: Set(settings.clipboardDisabledApps)) { bundleID in
                            if let bundleID { settings.clipboardDisabledApps.append(bundleID) }
                            showingAppPicker = false
                        }
                    }
            } header: {
                SettingsSectionHeader(.clipboardDisabledApplications)
            } footer: {
                Text("Clipboard changes from these apps won't be recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Button("Clear…", role: .destructive) { confirmingClear = true }
                } label: {
                    SettingsRowTitle(.clipboardDisabledApplications, "Clear history")
                    Text("Permanently remove every saved clip and image.")
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.clipboard)
        .confirmationDialog(
            "Clear clipboard history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                core.clipboardStore.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}

/// One excluded app; only the bundle ID is stored, so name and icon resolve on the fly.
private struct DisabledAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    @Environment(AppIndex.self) private var appIndex

    var body: some View {
        let (name, icon) = AppPresentation.resolve(bundleID: bundleID, in: appIndex)
        LabeledContent {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop excluding \(name)")
        } label: {
            Label {
                Text(name).lineLimit(1)
            } icon: {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
        }
    }
}
