import SwiftUI

/// The launcher item has no calendar state, so hiding it cannot hide the calendar item.
struct MenuBarLabel: View {
    let appName: String

    var body: some View {
        Image(systemName: "macwindow.on.rectangle")
            .accessibilityLabel(appName)
    }
}

/// Reading the coordinator here scopes Observation to the calendar label rather than either scene.
struct CalendarMenuBarLabel: View {
    let appName: String

    private var meeting: MeetingEvent? { AppCore.shared.calendarCoordinator.menuBarEvent }

    var body: some View {
        if let meeting {
            switch AppCore.shared.settings.calendarMenuBarDisplay {
            case .disabled:
                EmptyView()
            case .meetingIcon:
                Image(systemName: meeting.link?.provider.sfSymbol ?? "calendar")
                    .accessibilityLabel("\(appName): \(meeting.title)")
            case .meetingTitle:
                Text(text(for: meeting))
                    .accessibilityLabel("\(appName): \(text(for: meeting))")
            }
        } else {
            if AppCore.shared.settings.calendarMenuBarDisplay == .meetingTitle,
                hasUpcomingEvent
            {
                Image(systemName: "calendar")
                    .accessibilityLabel("\(appName) calendar")
            } else if AppCore.shared.settings.calendarMenuBarDisplay == .meetingTitle {
                Text("No upcoming events")
                    .accessibilityLabel("\(appName): No upcoming events")
            } else {
                Image(systemName: "calendar")
                    .accessibilityLabel("\(appName) calendar")
            }
        }
    }

    private var hasUpcomingEvent: Bool {
        AppCore.shared.calendarCoordinator.hasUpcomingMenuBarEvent
    }

    private func text(for meeting: MeetingEvent) -> String {
        let countdown = UpcomingWindow.countdown(
            to: meeting.start, now: AppCore.shared.meetingClock.now)
        return "\(MenuBarSummary.title(meeting.title)) • \(countdown)"
    }
}
