import SwiftUI

struct CloudSyncDevicesSection: View {
    @Environment(MainAppLink.self) private var mainApp
    @State private var name = ""
    @State private var removing: SyncDevice?

    private var cloud: MainAppStatus.CloudSync { mainApp.status.cloudSync }

    var body: some View {
        Section {
            LabeledContent {
                Text("This Mac")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(.quaternary, in: Capsule())
            } label: {
                TextField("Name", text: $name, prompt: Text("Name"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .onSubmit { mainApp.send(.renameThisMac(name)) }
                    .accessibilityLabel("This Mac's name")
                Text("Tinycast \(DeviceSyncSource.appVersion)")
            }
            ForEach(cloud.otherDevices) { device in
                LabeledContent {
                    Button("Remove…") { removing = device }
                } label: {
                    Text(device.name)
                    Text(
                        "Tinycast \(device.appVersion) · last synced \(device.lastSeen, format: .relative(presentation: .named))"
                    )
                }
            }
        } header: {
            SettingsSectionHeader(.iCloudSyncMacs)
        }
        .onAppear { name = cloud.thisMac }
        .onChange(of: cloud.thisMac) { _, updated in name = updated }
        .confirmationDialog(
            "Remove \(removing?.name ?? "")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let removing { mainApp.send(.removeSyncDevice(removing.id)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("That Mac stops using iCloud Sync until it's turned on there again. Its own data stays.")
        }
    }
}
