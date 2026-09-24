import SwiftUI

struct CalendarSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        Form {
            FeatureSwitchSection(
                anchor: .calendarCalendar,
                enableTitle: "Join meetings from Tinycast",
                enableSubtitle:
                    "Reads \(core.calendarCoordinator.span.possessivePhrase) events for join links. "
                    + "Nothing leaves this Mac.",
                isEnabled: enabledBinding,
                showsInLauncher: $settings.calendarShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            Section {
                Picker(selection: $settings.calendarLauncherLimit) {
                    ForEach(CalendarLauncherLimit.allCases) { limit in
                        Text(limit.title).tag(limit)
                    }
                } label: {
                    SettingsRowTitle(.calendarSchedule, "Upcoming meetings in launcher")
                }
            }
            .settingsEnabled(settings.calendarEnabled && settings.calendarShowInLauncher)

            if settings.calendarEnabled, store.access == .notDetermined {
                Section {
                    SettingsRow(
                        title: "Calendar access is needed",
                        subtitle: "Needed to read events and find join links."
                    ) {
                        Button("Allow Calendar Access…") {
                            core.calendarCoordinator.setCalendarEnabled(true)
                        }
                    }
                }
            } else if store.access == .denied {
                Section {
                    SettingsRow(
                        title: "Calendar access is off",
                        subtitle: "Allow it in Privacy & Security ▸ Calendars."
                    ) {
                        Button("Open System Settings…") { Permissions.openCalendarSettings() }
                    }
                }
            }

            Section {
                Toggle(isOn: $settings.calendarIncludesTomorrow) {
                    SettingsRowTitle(.calendarSchedule, "Include Tomorrow's Events")
                }
            } header: {
                SettingsSectionHeader(.calendarSchedule)
            }
            .settingsEnabled(settings.calendarEnabled)

            Section {
                Picker(selection: $settings.joinWindowMinutes) {
                    ForEach(JoinWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                } label: {
                    SettingsRowTitle(.calendarJoining, "Show the join card")
                    Text("Before and after a meeting starts.")
                }
                Toggle(isOn: $settings.autoJoinMeetings) {
                    SettingsRowTitle(.calendarJoining, "Auto Join Meetings")
                    Text("As they start.")
                }
                Toggle(isOn: $settings.autoJoinConfirms) {
                    SettingsRowTitle(.calendarJoining, "Confirm before joining")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.autoJoinMeetings)
                Toggle(isOn: $settings.cameraPreview) {
                    SettingsRowTitle(.calendarJoining, "Camera Preview")
                    Text("Before joining a meeting.")
                }
                MeetingBrowserPicker(selection: $settings.meetingBrowserBundleID)
            } header: {
                SettingsSectionHeader(.calendarJoining)
            }
            .settingsEnabled(settings.calendarEnabled)

            Section {
                Picker(selection: $settings.calendarMenuBarDisplay) {
                    ForEach(CalendarMenuBarDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Calendar in Menu Bar")
                    Text("Separate from the Tinycast icon.")
                }
                Picker(selection: $settings.menuBarEvents) {
                    ForEach(MenuBarEvents.allCases) { lead in
                        Text(lead.title).tag(lead)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Show Upcoming Events")
                    Text("When the next event appears.")
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Toggle(isOn: $settings.menuBarLinkedEventsOnly) {
                    SettingsRowTitle(.calendarMenuBar, "Only show events with meetings")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Toggle(isOn: $settings.calendarMenuBarHidesWhenEmpty) {
                    SettingsRowTitle(.calendarMenuBar, "Hide when there are no upcoming events")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Picker(selection: $settings.hideCurrentEvent) {
                    ForEach(HideCurrentEvent.allCases) { hide in
                        Text(hide.title).tag(hide)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Hide Current Event")
                    Text("Once it has started.")
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
            } header: {
                SettingsSectionHeader(.calendarMenuBar)
            }
            .settingsEnabled(settings.calendarEnabled)

            FeatureCommandsSection(owner: .calendar, anchor: .calendarCommands)
                .settingsEnabled(settings.calendarEnabled)

            CalendarPickerSection()
                .settingsEnabled(settings.calendarEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.calendar)
        .releasesFocusOnOutsideClick()
        // The snapshot is only reloaded while the feature runs, so a grant made in Settings lands here.
        .onAppear { store.refreshAccess() }
    }

    /// Routed through the coordinator so enabling, which is also consent, confirms first.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.calendarEnabled },
            set: { core.calendarCoordinator.setCalendarEnabled($0) }
        )
    }
}

private struct MeetingBrowserPicker: View {
    @Binding var selection: String?
    @State private var browsers: [MeetingLauncher.Browser] = []

    var body: some View {
        Picker(selection: installedSelection) {
            Text("Default Browser").tag(String?.none)
            Divider()
            ForEach(browsers) { browser in
                Text(browser.name).tag(Optional(browser.id))
            }
        } label: {
            SettingsRowTitle(.calendarJoining, "Open Meeting Links In")
            Text("When no meeting app handles the link.")
        }
        .onAppear { browsers = MeetingLauncher.installedBrowsers() }
    }

    /// A browser since removed reads as the default, which is what joining falls back to.
    private var installedSelection: Binding<String?> {
        Binding(
            get: { browsers.contains { $0.id == selection } ? selection : nil },
            set: { selection = $0 }
        )
    }
}

/// Machine-local by nature, so these live on the store and never travel in a backup.
private struct CalendarPickerSection: View {
    @Environment(CalendarStore.self) private var store
    @State private var query = ""

    private var calendars: [MeetingCalendar] {
        guard !query.isEmpty else { return store.calendars }
        return store.calendars.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.accountName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Section {
            SettingsFilterField(prompt: "Search calendars…", query: $query)

            if calendars.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // One row holding a lazy stack: a `Form` realizes every row it is handed.
                LazyVStack(spacing: 0) {
                    ForEach(calendars) { calendar in
                        if calendar.id != calendars.first?.id { Divider() }
                        CalendarRow(calendar: calendar)
                            .padding(.vertical, Self.rowPadding)
                    }
                }
                .padding(.vertical, -Self.rowPadding)
            }
        } header: {
            SettingsSectionHeader(.calendarCalendars)
        }
    }

    /// A grouped `Form` row's own vertical padding.
    private static let rowPadding: CGFloat = 15

    private var emptyMessage: String {
        if !query.isEmpty { return "No matches for “\(query)”." }
        return store.access == .granted ? "No calendars on this Mac." : "Nothing to show yet."
    }
}

private struct CalendarRow: View {
    let calendar: MeetingCalendar
    @Environment(CalendarStore.self) private var store

    var body: some View {
        SettingsRow(title: calendar.title, subtitle: calendar.accountName) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Include \(calendar.title) in meetings")
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(calendar) },
            set: { store.setEnabled($0, for: calendar) }
        )
    }
}
