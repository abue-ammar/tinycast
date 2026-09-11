import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.clipboardEnabled) {
                    SettingsRowTitle(.clipboardClipboard, "Enable Clipboard History")
                    Text("Record what you copy, so you can paste anything back from the browser.")
                }
            } header: {
                SettingsSectionHeader(.clipboardClipboard)
            }

            FeatureCommandsSection(owner: .clipboard, anchor: .clipboardCommands)
                .settingsEnabled(settings.clipboardEnabled)

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
                Toggle(isOn: $settings.clipboardTextSearchEnabled) {
                    SettingsRowTitle(.clipboardHistory, "Search text in images and PDFs")
                    Text("Recognize text on this Mac while idle and include it in clipboard searches.")
                }
                Picker(selection: $settings.clipboardDefaultAction) {
                    ForEach(ClipboardDefaultAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                } label: {
                    SettingsRowTitle(.clipboardHistory, "Default action")
                    Text("What ↵ does on an entry; ⌘↵ does the other one.")
                }
            } header: {
                SettingsSectionHeader(.clipboardHistory)
            }
            .settingsEnabled(settings.clipboardEnabled)

            DisabledApplicationsSection(
                bundleIDs: $settings.clipboardDisabledApps,
                anchor: .clipboardDisabledApplications,
                footer: "Clipboard changes from these apps won't be recorded."
            )
            .settingsEnabled(settings.clipboardEnabled)

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
                core.clipboardCoordinator.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}
