import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(\.locale) private var localizationLocale
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var calendarAccess = Permissions.calendarAccess()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Label(
                        accessibilityTrusted ? String(
                            localized: "Granted",
                            bundle: .appLanguage) : String(
                            localized: "Not granted",
                            bundle: .appLanguage),
                        systemImage: accessibilityTrusted
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
                } label: {
                    SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                    Text("Lets Tinycast paste a clipboard item into the app you were using.")
                }

                LabeledContent {
                    Button(accessibilityTrusted ? String(
                        localized: "Open…",
                        bundle: .appLanguage) : String(
                        localized: "Grant Access…",
                        bundle: .appLanguage)) {
                        Permissions.openAccessibilitySettings()
                    }
                } label: {
                    Text(
                        accessibilityTrusted
                            ? String(localized: "Manage in System Settings", bundle: .appLanguage)
                            : String(localized: "Grant access", bundle: .appLanguage))
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
                    Button("Open…") { Permissions.openCalendarSettings() }
                } label: {
                    Text("Manage in System Settings")
                    // Only the Calendar pane's own switch may ask for this, so this never prompts.
                    Text("Opens Privacy & Security › Calendars.")
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

    private var calendarStatus: (title: String, symbol: String, tint: Color) {
        switch calendarAccess {
        case .granted: return (String(localized: "Granted", bundle: .appLanguage), "checkmark.circle.fill", .green)
        case .notDetermined: return (String(
            localized: "Not asked yet",
            bundle: .appLanguage), "questionmark.circle.fill", .secondary)
        case .denied: return (String(localized: "Not granted", bundle: .appLanguage), "exclamationmark.triangle.fill", .orange)
        }
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let access = Permissions.calendarAccess()
        if access != calendarAccess { calendarAccess = access }
    }
}
