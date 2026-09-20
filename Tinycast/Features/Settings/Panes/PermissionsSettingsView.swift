import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var calendarAccess = Permissions.calendarAccess()
    @State private var remindersAccess = Permissions.remindersAccess()
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

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        Label(remindersStatus.title, systemImage: remindersStatus.symbol)
                            .foregroundStyle(remindersStatus.tint)
                        Button(remindersNeedsPrompt ? "Grant Access…" : "Open…") {
                            if remindersNeedsPrompt {
                                requestReminders()
                            } else {
                                Permissions.openRemindersSettings()
                            }
                        }
                        .help(
                            remindersNeedsPrompt
                                ? "Asks macOS for access, so the Apple Reminders extension can work."
                                : "Opens Privacy & Security › Reminders.")
                    }
                } label: {
                    SettingsRowTitle(.permissionsReminders, "Reminders")
                    Text("Lets the Apple Reminders extension work.")
                }
            } header: {
                SettingsSectionHeader(.permissionsReminders)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var calendarNeedsPrompt: Bool { calendarAccess == .notDetermined }
    private var remindersNeedsPrompt: Bool { remindersAccess == .notDetermined }

    private var accessibilityStatus: (title: String, symbol: String, tint: Color) {
        accessibilityTrusted
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

    private var remindersStatus: (title: String, symbol: String, tint: Color) {
        switch remindersAccess {
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
        let reminders = Permissions.remindersAccess()
        if reminders != remindersAccess { remindersAccess = reminders }
    }

    private func requestReminders() {
        Task {
            guard
                await core.confirm(
                    title: "Enable Reminders?",
                    message: "Lets the Apple Reminders extension read and create your reminders.",
                    symbol: "checklist", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }
            _ = await Permissions.requestRemindersAccess()
            refresh()
        }
    }
}
