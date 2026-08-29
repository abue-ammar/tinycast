import SwiftUI

/// Reading the coordinator here scopes Observation to the label rather than the scene.
struct MenuBarLabel: View {
    let appName: String

    private var meeting: MeetingEvent? { AppCore.shared.calendarCoordinator.menuBarEvent }

    var body: some View {
        if let meeting {
            Label(text(for: meeting), systemImage: meeting.link?.provider.sfSymbol ?? "calendar")
                .accessibilityLabel("\(appName): \(text(for: meeting))")
        } else {
            Image(systemName: "macwindow.on.rectangle")
                .accessibilityLabel(appName)
        }
    }

    private func text(for meeting: MeetingEvent) -> String {
        let countdown = UpcomingWindow.countdown(
            to: meeting.start, now: AppCore.shared.meetingClock.now)
        return "\(MenuBarSummary.title(meeting.title)) · \(countdown)"
    }
}
