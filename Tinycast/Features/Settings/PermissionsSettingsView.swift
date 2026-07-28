import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var inputMonitoringTrusted = Permissions.isInputMonitoringTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPane(
            title: "Permissions",
            subtitle: "Access Tinycast needs to work with other apps and snippets."
        ) {
            SettingsCard(header: "Accessibility") {
                SettingsRow(
                    title: "Accessibility",
                    subtitle: "Lets Tinycast paste clipboard items and expanded snippets into the app you are using.",
                    systemImage: "accessibility",
                    tint: .blue
                ) {
                    statusBadge(isGranted: accessibilityTrusted)
                }
                SettingsDivider()
                SettingsRow(
                    title: accessibilityTrusted ? "Manage in System Settings" : "Grant access",
                    subtitle: "Opens Privacy & Security › Accessibility.",
                    systemImage: "arrow.up.forward.app",
                    tint: .secondary
                ) {
                    Button(accessibilityTrusted ? "Open…" : "Open Settings…") {
                        Permissions.openAccessibilitySettings()
                    }
                }
            }

            SettingsCard(header: "Input Monitoring") {
                SettingsRow(
                    title: "Input Monitoring",
                    subtitle: "Required for Snippets auto-expansion keywords (e.g. !notes) to detect keystrokes in other apps.",
                    systemImage: "keyboard",
                    tint: .purple
                ) {
                    statusBadge(isGranted: inputMonitoringTrusted)
                }
                SettingsDivider()
                SettingsRow(
                    title: inputMonitoringTrusted ? "Manage in System Settings" : "Grant access",
                    subtitle: "Opens Privacy & Security › Input Monitoring.",
                    systemImage: "arrow.up.forward.app",
                    tint: .secondary
                ) {
                    Button(inputMonitoringTrusted ? "Open…" : "Open Settings…") {
                        Permissions.requestInputMonitoringPrompt()
                        Permissions.openInputMonitoringSettings()
                    }
                }
            }
        }
        .onAppear { refreshPermissions() }
        .onReceive(refreshTimer) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        let acc = Permissions.isAccessibilityTrusted()
        if acc != accessibilityTrusted { accessibilityTrusted = acc }
        let input = Permissions.isInputMonitoringTrusted()
        if input != inputMonitoringTrusted { inputMonitoringTrusted = input }
    }

    private func statusBadge(isGranted: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            Image(
                systemName: isGranted
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            Text(isGranted ? "Granted" : "Not granted")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isGranted ? Color.green : Color.orange)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule().fill((isGranted ? Color.green : Color.orange).opacity(0.14))
        )
    }
}
