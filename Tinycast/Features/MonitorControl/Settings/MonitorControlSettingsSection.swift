import SwiftUI

struct MonitorControlSettingsSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MonitorControlCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: $settings.externalMonitorControlsEnabled) {
                SettingsRowTitle(.monitorControlExternalMonitors, "Enable external monitor control")
            }
            .toggleStyle(MonitorControlToggleStyle())
            if settings.externalMonitorControlsEnabled {
                Toggle(isOn: $settings.externalMonitorFineAdjustments) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        SettingsRowTitle(.monitorControlExternalMonitors, "Fine-grained adjustments")
                        Text(settings.externalMonitorFineAdjustments
                             ? "Smaller brightness and volume steps. Hold Option–Shift for larger steps."
                             : "Standard brightness and volume steps. Hold Option–Shift for smaller steps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(MonitorControlToggleStyle())
                if coordinator.displays.isEmpty {
                    Text(coordinator.status).foregroundStyle(.secondary)
                } else {
                    LabeledContent("Detected monitors", value: coordinator.displays.map(\.name).joined(separator: ", "))
                }
                if !coordinator.hasPermission {
                    Text("Allow Accessibility access in Settings → Permissions to use the keyboard controls.")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if settings.externalMonitorControlsEnabled {
                Text("To adjust brightness, move the pointer onto the monitor you want to change.")
            }
        }
        .settingsAnchor(.monitorControlExternalMonitors)
    }
}
