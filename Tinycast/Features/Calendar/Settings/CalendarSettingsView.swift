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
                    "Reads \(core.calendarCoordinator.span.possessivePhrase) events to find join "
                    + "links. Nothing leaves this Mac.",
                launcherSubtitle: "List individual meetings alongside apps and commands.",
                isEnabled: enabledBinding,
                showsInLauncher: $settings.calendarShowInLauncher)

            Section {
                Picker(selection: $settings.calendarLauncherLimit) {
                    ForEach(CalendarLauncherLimit.allCases) { limit in
                        Text(limit.title).tag(limit)
                    }
                } label: {
                    SettingsRowTitle(.calendarSchedule, "Upcoming meetings in launcher")
                    Text("Choose how many upcoming meetings appear alongside apps and commands.")
                }
            }
            .settingsEnabled(settings.calendarEnabled && settings.calendarShowInLauncher)

            if store.access == .denied {
                Section {
                    SettingsRow(
                        title: "Calendar access is off",
                        subtitle: "Turn Tinycast on under Privacy & Security ▸ Calendars."
                    ) {
                        Button("Open System Settings…") { Permissions.openCalendarSettings() }
                    }
                }
            }

            Section {
                Toggle(isOn: $settings.calendarIncludesTomorrow) {
                    SettingsRowTitle(.calendarSchedule, "Include Tomorrow's Events")
                    Text("Read tomorrow as well as the rest of today, everywhere meetings appear.")
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
                    Text("How early the card appears, and how long past the start it stays.")
                }
                Toggle(isOn: $settings.autoJoinMeetings) {
                    SettingsRowTitle(.calendarJoining, "Auto Join Meetings")
                    Text("Automatically join meetings as they start.")
                }
                Toggle(isOn: $settings.autoJoinConfirms) {
                    SettingsRowTitle(.calendarJoining, "Confirm before joining")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.autoJoinMeetings)
                Toggle(isOn: $settings.cameraPreview) {
                    SettingsRowTitle(.calendarJoining, "Camera Preview")
                    Text("Open camera preview before joining meetings.")
                }
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
                    Text(
                        "Its own menu bar item, showing a meeting icon or its title and countdown."
                    )
                }
                Picker(selection: $settings.menuBarEvents) {
                    ForEach(MenuBarEvents.allCases) { lead in
                        Text(lead.title).tag(lead)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Show Upcoming Events")
                    Text(
                        "When the next event reaches the menu bar. Today includes the next 30 "
                            + "minutes after midnight."
                    )
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Toggle(isOn: $settings.menuBarLinkedEventsOnly) {
                    SettingsRowTitle(.calendarMenuBar, "Only show events with meetings")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Picker(selection: $settings.hideCurrentEvent) {
                    ForEach(HideCurrentEvent.allCases) { hide in
                        Text(hide.title).tag(hide)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Hide Current Event")
                    Text("Choose whether to hide a started event or show its time left.")
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
            } header: {
                SettingsSectionHeader(.calendarMenuBar)
            }
            .settingsEnabled(settings.calendarEnabled)

            CalendarCommandsSection()
                .settingsEnabled(settings.calendarEnabled)

            CalendarPickerSection()
                .settingsEnabled(settings.calendarEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.calendar)
        .releasesFocusOnOutsideClick()
    }

    /// Routed through the coordinator so enabling, which is also consent, confirms first.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.calendarEnabled },
            set: { core.calendarCoordinator.setCalendarEnabled($0) }
        )
    }
}

/// The feature's own commands, so a shortcut or an alias is set beside what it acts on.
private struct CalendarCommandsSection: View {
    @Environment(VisibilityStore.self) private var visibility

    private let entries = [
        CommandID.joinNextMeeting, .mySchedule, .createEvent, .copyMeetingLink, .openInCalendar
    ]
    .compactMap(CommandCatalog.entry(for:))

    var body: some View {
        Section {
            ForEach(entries) { entry in
                SettingsRow(title: entry.name) {
                    AppIconView(app: entry)
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                } trailing: {
                    AliasField(entry: entry)
                    if let action = entry.hotKeyAction {
                        ShortcutRecorder(action: action)
                    }
                    Toggle("", isOn: visibilityBinding(entry))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("Show \(entry.name) in launcher")
                }
            }
        } header: {
            SettingsSectionHeader(.calendarCalendar)
        } footer: {
            Text("A shortcut works even when its command is hidden from the launcher.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func visibilityBinding(_ entry: AppEntry) -> Binding<Bool> {
        Binding(
            get: { visibility.isItemVisible(entry) },
            set: { visibility.setItemVisible($0, for: entry) }
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
