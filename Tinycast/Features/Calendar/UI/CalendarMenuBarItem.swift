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
            HStack(spacing: Theme.Spacing.xs) {
                if let color = meeting.calendarColor {
                    Image(nsImage: color.menuBarDot).accessibilityHidden(true)
                }
                title(summary(for: meeting))
            }
        case (.meetingTitle, nil)
        where !AppCore.shared.calendarCoordinator.hasUpcomingMenuBarEvent:
            title(String(localized: "No upcoming events"))
        case (_, nil):
            icon("calendar", describing: String(localized: "no current meeting"))
        }
    }

    private func icon(_ symbol: String, describing description: String) -> some View {
        Image(systemName: symbol).accessibilityLabel(Text(verbatim: "\(appName): \(description)"))
    }

    private func title(_ text: String) -> some View {
        Text(text).accessibilityLabel(Text(verbatim: "\(appName): \(text)"))
    }

    private func summary(for meeting: MeetingEvent) -> String {
        let countdown = UpcomingWindow.menuBarCountdown(
            for: meeting, now: AppCore.shared.meetingClock.now, locale: .current)
        return "\(MenuBarSummary.title(meeting.title)) • \(countdown)"
    }
}

/// Calendar actions only: the launcher item carries the app's menu, and neither repeats the other.
struct CalendarMenuBarMenu: View {
    var body: some View {
        // A macOS menu drops a label's icon unless the style asks for it.
        Group {
            let coordinator = AppCore.shared.calendarCoordinator
            if let meeting = coordinator.menuBarEvent {
                Section {
                    if let link = meeting.link {
                        Button("Join \(meeting.title)", systemImage: link.provider.sfSymbol) {
                            coordinator.join(meeting)
                        }
                    }
                    Button("Open in Calendar", systemImage: "calendar") {
                        coordinator.openInCalendar(meeting)
                    }
                    Button("Dismiss Event", systemImage: "xmark.circle") {
                        coordinator.dismissMenuBarEvent(meeting)
                    }
                }
            }
            MenuBarAgenda()
            Section {
                Button("My Schedule", systemImage: "calendar.day.timeline.left") {
                    coordinator.showSchedule()
                }
                .keyboardShortcut("o")
                Button("Calendar Settings…", systemImage: "gearshape") {
                    AppCore.shared.settingsCoordinator.showSettings(tab: .calendar)
                }
                .keyboardShortcut(",")
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

private struct MenuBarAgenda: View {
    var body: some View {
        let now = AppCore.shared.meetingClock.now
        ForEach(AppCore.shared.calendarCoordinator.menuBarAgenda) { group in
            Section(group.day.title(calendar: .current)) {
                ForEach(group.meetings) { meeting in
                    Button {
                        AppCore.shared.calendarCoordinator.join(meeting)
                    } label: {
                        Label {
                            Text(verbatim: "\(MeetingTimeFormat.range(of: meeting)) \(meeting.title)")
                        } icon: {
                            CalendarSymbol(
                                name: meeting.isInProgress(now: now) ? "circle.fill" : "circle",
                                color: meeting.calendarColor)
                        }
                    }
                }
            }
        }
    }
}

/// A symbol in the event's calendar colour, where a menu would otherwise ink it like its text.
private struct CalendarSymbol: View {
    let name: String
    let color: MeetingEvent.CalendarColor?

    var body: some View {
        if let image = color?.menuSymbol(name) {
            Image(nsImage: image)
        } else {
            Image(systemName: name)
        }
    }
}

/// Neither image is a template, so the status bar and its menu keep the colour rather than ink it.
extension MeetingEvent.CalendarColor {
    fileprivate var menuBarDot: NSImage {
        let size = NSSize(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
        let image = NSImage(size: size, flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    fileprivate func menuSymbol(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular
        ).applying(NSImage.SymbolConfiguration(paletteColors: [nsColor]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }
}
