import SwiftUI

/// Reading the coordinator here scopes Observation to the calendar label rather than either scene.
struct CalendarMenuBarLabel: View {
    let appName: String

    private var display: CalendarMenuBarDisplay { AppCore.shared.settings.calendarMenuBarDisplay }
    private var meeting: MeetingEvent? { AppCore.shared.calendarCoordinator.menuBarEvent }

    var body: some View {
        switch (display, meeting) {
        case (.disabled, _):
            EmptyView()
        case (.meetingIcon, let meeting?):
            icon(meeting.link?.provider.sfSymbol ?? "calendar", describing: meeting.title)
        case (.meetingTitle, let meeting?):
            title(summary(for: meeting))
        case (.meetingTitle, nil)
        where !AppCore.shared.calendarCoordinator.hasUpcomingMenuBarEvent:
            title("No upcoming events")
        case (_, nil):
            icon("calendar", describing: "no current meeting")
        }
    }

    private func icon(_ symbol: String, describing description: String) -> some View {
        Image(systemName: symbol).accessibilityLabel("\(appName): \(description)")
    }

    private func title(_ text: String) -> some View {
        Text(text).accessibilityLabel("\(appName): \(text)")
    }

    private func summary(for meeting: MeetingEvent) -> String {
        let countdown = UpcomingWindow.menuBarCountdown(
            for: meeting, now: AppCore.shared.meetingClock.now)
        return "\(MenuBarSummary.title(meeting.title)) • \(countdown)"
    }
}

/// Calendar actions only: the launcher item carries the app's menu, and neither repeats the other.
struct CalendarMenuBarMenu: View {
    var body: some View {
        if let meeting = AppCore.shared.calendarCoordinator.menuBarEvent {
            if meeting.link != nil {
                Button("Join \(meeting.title)") {
                    AppCore.shared.calendarCoordinator.join(meeting)
                }
            }
            Button("Open in Calendar...") {
                AppCore.shared.calendarCoordinator.openInCalendar(meeting)
            }
            Divider()
        }
        Button("My Schedule") { AppCore.shared.calendarCoordinator.showSchedule() }
        Button("Calendar Settings...") {
            AppCore.shared.settingsCoordinator.showSettings(tab: .calendar)
        }
    }
}
