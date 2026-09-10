import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var calendarAccess = Permissions.calendarAccess()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Label(
                        accessibilityTrusted ? "Granted" : "Not granted",
                        systemImage: accessibilityTrusted
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
                } label: {
                    SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                    Text("Lets Tinycast paste a clipboard item into the app you were using.")
                }

                LabeledContent {
                    Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                        Permissions.openAccessibilitySettings()
                    }
                } label: {
                    Text(accessibilityTrusted ? "Manage in System Settings" : "Grant access")
                    Text("Opens Privacy & Security › Accessibility.")
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            } footer: {
                Text("Access Tinycast needs to work with other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Label(calendarStatus.title, systemImage: calendarStatus.symbol)
                        .foregroundStyle(calendarStatus.tint)
                } label: {
                    SettingsRowTitle(.permissionsCalendars, "Calendars")
                    Text("Lets Tinycast find the join link for the meeting you are about to be in.")
                }

                LabeledContent {
                    Button(calendarNeedsPrompt ? "Grant Access…" : "Open…") {
                        // Settings lists no app TCC was never asked about, so asking is the way in.
                        if calendarNeedsPrompt {
                            core.calendarCoordinator.setCalendarEnabled(true)
                        } else {
                            Permissions.openCalendarSettings()
                        }
                    }
                } label: {
                    Text(calendarNeedsPrompt ? "Grant access" : "Manage in System Settings")
                    Text(
                        calendarNeedsPrompt
                            ? "Turns the calendar on, then asks macOS for access."
                            : "Opens Privacy & Security › Calendars.")
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
        let access = Permissions.calendarAccess()
        if access != calendarAccess { calendarAccess = access }
    }
}
