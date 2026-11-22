import SwiftUI

struct CloudSyncSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(MainAppLink.self) private var mainApp
    /// The switch's requested position while its confirmation is up.
    @State private var requestedEnabled: Bool?
    @State private var confirmingDelete = false

    private var sync: CloudSyncCoordinator { core.cloudSyncCoordinator }
    /// The session runs in the main app; this process only keeps the switches.
    private var cloud: MainAppStatus.CloudSync { mainApp.status.cloudSync }

    private var switchBinding: Binding<Bool> {
        Binding(get: { sync.isEnabled }, set: { requestedEnabled = $0 })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: switchBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .iCloudSyncSwitch, title: "Sync with iCloud",
                        subtitle:
                            "Keep settings and content the same on every Mac signed in to your iCloud account."
                    )
                }
                .disabled(cloud.status == .unavailable(.unsignedBuild))
                CloudSyncStatusLine(
                    status: cloud.status, stopReason: cloud.stopReason,
                    retry: { mainApp.send(.refreshICloudSync) })
            }
            .settingsAnchor(.iCloudSyncSwitch)

            Section {
                CloudSyncCategoryList(group: .content)
            } header: {
                SettingsSectionHeader(.iCloudSyncContent)
            } footer: {
                if !sync.isEnabled {
                    Text("Choose what syncs before you turn iCloud Sync on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                CloudSyncCategoryList(group: .general)
            } header: {
                SettingsSectionHeader(.iCloudSyncGeneral)
            }
            Section {
                CloudSyncCategoryList(group: .always)
            } header: {
                SettingsSectionHeader(.iCloudSyncAlways)
            }

            Section {
                ForEach(SyncExclusion.allCases, id: \.self) { exclusion in
                    SettingsInfoRow(
                        title: exclusion.title, symbol: exclusion.symbol, tint: exclusion.tint,
                        detail: exclusion.detail)
                }
            } header: {
                SettingsSectionHeader(.iCloudSyncNotSynced)
            }

            if sync.isEnabled {
                CloudSyncDevicesSection()
                Section {
                    LabeledContent {
                        Button("Delete…", role: .destructive) { confirmingDelete = true }
                    } label: {
                        SettingsRowTitle(.iCloudSyncData, "Delete iCloud Data")
                        Text("Removes everything Tinycast stored in iCloud. Each Mac keeps its own data.")
                    }
                } header: {
                    SettingsSectionHeader(.iCloudSyncData)
                } footer: {
                    Text(
                        """
                        Synced content is end-to-end encrypted with iCloud. Clipboard history, \
                        passwords and API keys never leave this Mac.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.iCloudSync)
        .onAppear { mainApp.send(.refreshICloudSync) }
        .confirmationDialog(
            requestedEnabled == true ? "Turn on iCloud Sync?" : "Turn off iCloud Sync?",
            isPresented: Binding(
                get: { requestedEnabled != nil }, set: { if !$0 { requestedEnabled = nil } }),
            titleVisibility: .visible
        ) {
            if requestedEnabled == true {
                Button("Turn On") { mainApp.send(.setICloudSyncEnabled(true)) }
            } else {
                Button("Turn Off", role: .destructive) { mainApp.send(.setICloudSyncEnabled(false)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                requestedEnabled == true
                    ? "The checked items sync with every Mac signed in to this iCloud account."
                    : "This Mac stops syncing. Its data, and the copy in iCloud, stay as they are.")
        }
        .confirmationDialog("Delete iCloud data?", isPresented: $confirmingDelete, titleVisibility: .visible)
        {
            Button("Delete", role: .destructive) { mainApp.send(.deleteICloudData) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This deletes Tinycast's data and Macs from iCloud and turns off sync. Data on each Mac stays."
            )
        }
    }
}
