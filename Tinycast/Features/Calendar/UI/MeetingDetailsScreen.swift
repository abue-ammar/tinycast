import SwiftUI

/// One meeting's page. ↵, ⌘↵, ⌘O and ⌘K act on it exactly as on its schedule row.
struct MeetingDetailsScreen: PaletteScreen {
    let store: CalendarStore
    let core: AppCore

    private var meeting: MeetingEvent? {
        store.details.flatMap { store.event(id: $0.meetingID) }
    }

    var rows: [MeetingEvent] { meeting.map { [$0] } ?? [] }

    var primaryActionTitle: String {
        meeting?.link == nil ? String(localized: "Open in Calendar") : String(localized: "Join Meeting")
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        meeting.map { MeetingActionsMenu.content(meeting: $0, core: core, offersDetails: false) }
    }

    func activate(at selection: Int) {
        guard let meeting else { return }
        core.calendarCoordinator.join(meeting)
    }

    func secondary(at selection: Int) -> Bool {
        guard let meeting else { return false }
        return MeetingActionsMenu.secondary(meeting: meeting, core: core)
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let meeting else { return false }
        return MeetingActionsMenu.perform(shortcut, meeting: meeting, core: core, offersDetails: false)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard let details = store.details, let meeting = store.event(id: details.meetingID) else {
            return AnyView(EmptyResults(text: String(localized: "This meeting is no longer available")))
        }
        return AnyView(MeetingDetailsView(meeting: meeting, details: details))
    }
}
