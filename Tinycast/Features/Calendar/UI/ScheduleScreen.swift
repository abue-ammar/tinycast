import SwiftUI

/// My Schedule: today and tomorrow, filtered by the query. Enter joins, ⌘K carries the rest.
struct ScheduleScreen: PaletteScreen {
    let store: CalendarStore
    let clock: MeetingClock
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    var rows: [MeetingEvent] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        let agenda = UpcomingWindow.agenda(from: store.events)
        guard !query.isEmpty else { return agenda }
        return agenda.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.calendarName.localizedCaseInsensitiveContains(query)
        }
    }

    /// A meeting with no link has nowhere to join, so the pill offers what it can instead.
    var primaryActionTitle: String {
        meeting(at: vm.selection)?.link == nil ? "Open in Calendar" : "Join Meeting"
    }

    private func meeting(at selection: Int) -> MeetingEvent? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let meeting = meeting(at: selection) else { return nil }
        return MeetingActionsMenu.content(meeting: meeting, core: core)
    }

    func activate(at selection: Int) {
        guard let meeting = meeting(at: selection) else { return }
        core.calendarCoordinator.activateMeeting(id: meeting.id)
    }

    /// ⌘↵ — copy the link, for the "what's the link?" message rather than the call itself.
    func secondary(at selection: Int) -> Bool {
        guard let meeting = meeting(at: selection), meeting.link != nil else { return false }
        core.calendarCoordinator.copyLink(meeting)
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            ScheduleList(
                results: rows,
                selectedID: meeting(at: selection)?.id,
                now: clock.now,
                scroll: scroll,
                onActivate: { activate(at: rows.firstIndex(of: $0) ?? selection) },
                onActions: { meeting in
                    if let index = rows.firstIndex(of: meeting) { vm.selection = index }
                    openActions()
                }
            )
        }
    }

    /// Names why the list is empty: no access reads very differently from a free afternoon.
    private var emptyMessage: String {
        if store.access != .granted { return "Tinycast has no access to your calendar" }
        if !vm.query.trimmingCharacters(in: .whitespaces).isEmpty { return "No matching meetings" }
        return "Nothing scheduled today or tomorrow"
    }
}
