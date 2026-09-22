import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var inputMonitoringGranted = Permissions.isInputMonitoringGranted()
    @State private var calendarAccess = Permissions.calendarAccess()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        Label(accessibilityStatus.title, systemImage: accessibilityStatus.symbol)
                            .foregroundStyle(accessibilityStatus.tint)
                        Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                            Permissions.openAccessibilitySettings()
                        }
                        .help("Opens Privacy & Security › Accessibility.")
                    }
                } label: {
                    SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                    Text("Pastes into the app you were using.")
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        Label(inputMonitoringStatus.title, systemImage: inputMonitoringStatus.symbol)
                            .foregroundStyle(inputMonitoringStatus.tint)
                        Button(inputMonitoringGranted ? "Open…" : "Grant Access…") {
                            if inputMonitoringGranted {
                                Permissions.openInputMonitoringSettings()
                            } else {
                                Permissions.requestInputMonitoring()
                            }
                            refresh()
                        }
                        .help("Opens Privacy & Security › Input Monitoring.")
                    }
                } label: {
                    SettingsRowTitle(.permissionsInputMonitoring, "Input Monitoring")
                    Text("Detects modifier-only hotkeys outside Tinycast.")
                }
            } header: {
                SettingsSectionHeader(.permissionsInputMonitoring)
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        Label(calendarStatus.title, systemImage: calendarStatus.symbol)
                            .foregroundStyle(calendarStatus.tint)
                        Button(calendarNeedsPrompt ? "Grant Access…" : "Open…") {
                            // Settings lists no app TCC was never asked about, so asking is the way in.
                            if calendarNeedsPrompt {
                                core.calendarCoordinator.setCalendarEnabled(true)
                            } else {
                                Permissions.openCalendarSettings()
                            }
                        }
                        .help(
                            calendarNeedsPrompt
                                ? "Turns the calendar on, then asks macOS for access."
                                : "Opens Privacy & Security › Calendars.")
                    }
                } label: {
                    SettingsRowTitle(.permissionsCalendars, "Calendars")
                    Text("Finds the join link for your next meeting.")
                }
            } header: {
                SettingsSectionHeader(.permissionsCalendars)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var calendarNeedsPrompt: Bool { calendarAccess == .notDetermined }

    private var accessibilityStatus: (title: String, symbol: String, tint: Color) {
        accessibilityTrusted
            ? ("Granted", "checkmark.circle.fill", .green)
            : ("Not granted", "exclamationmark.triangle.fill", .orange)
    }

    private var inputMonitoringStatus: (title: String, symbol: String, tint: Color) {
        inputMonitoringGranted
            ? ("Granted", "checkmark.circle.fill", .green)
            : ("Not granted", "exclamationmark.triangle.fill", .orange)
    }

    private var calendarStatus: (title: String, symbol: String, tint: Color) {
        switch calendarAccess {
        case .granted: return ("Granted", "checkmark.circle.fill", .green)
        case .notDetermined: return ("Not asked yet", "questionmark.circle.fill", .secondary)
        case .denied: return ("Not granted", "exclamationmark.triangle.fill", .orange)
        }
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let granted = Permissions.isInputMonitoringGranted()
        if granted != inputMonitoringGranted { inputMonitoringGranted = granted }
        let access = Permissions.calendarAccess()
        if access != calendarAccess { calendarAccess = access }
    }
}
