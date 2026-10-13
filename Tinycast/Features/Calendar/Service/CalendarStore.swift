import AppKit
import EventKit

@MainActor
@Observable
final class CalendarStore {
    /// Flattened occurrences over `span`, newest query wins.
    private(set) var events: [MeetingEvent] = []
    private(set) var calendars: [MeetingCalendar] = []
    private(set) var access: CalendarAccess = Permissions.calendarAccess()
    /// The details page's meeting, re-read with every reload so an edit never shows stale.
    private(set) var details: MeetingDetails?

    /// Changing it re-reads: nothing may filter a snapshot into a span it never fetched.
    var span: MeetingSpan = .todayAndTomorrow {
        didSet {
            guard span != oldValue, lastReloadAt != nil else { return }
            reload()
        }
    }

    /// Fired whenever `events` changes, so the launcher's meeting slice is republished.
    @ObservationIgnored var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let hiddenKey = "hiddenMeetingCalendars"
    /// Exclusions, not inclusions, so a calendar added after this was written defaults to on.
    private var hiddenCalendarIDs: Set<String>

    /// Built on first use, so a Mac with the feature off never loads EventKit at launch.
    @ObservationIgnored private var eventStore: EKEventStore?
    @ObservationIgnored private var changeObserver: NotificationToken?
    @ObservationIgnored private var wakeObserver: NotificationToken?
    @ObservationIgnored private var lastReloadAt: Date?

    /// Covers the day rolling over and a Mac that slept; edits come from EventKit.
    private static let staleAfter: TimeInterval = 10 * 60

    init() {
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    }

    /// TCC sends nothing when a grant changes in Settings, so anything acting on `access` re-reads.
    func refreshAccess() {
        access = Permissions.calendarAccess()
    }

    // MARK: - Lifecycle

    func start() {
        refreshAccess()
        guard access == .granted else { return }
        observeWake()
        // Deferred: the first EventKit query pays for its XPC warm-up, and launch protects itself.
        Task { reload() }
    }

    func stop() {
        changeObserver = nil
        wakeObserver = nil
        eventStore = nil
        lastReloadAt = nil
        publish([])
        calendars = []
        details = nil
    }

    /// Tinycast's own consent dialog has already been accepted by the time this runs.
    func requestAccess() async -> Bool {
        let granted = await Permissions.requestCalendarAccess()
        refreshAccess()
        guard granted else { return false }
        // A store built before the grant never sees the new calendars; drop it and rebuild.
        changeObserver = nil
        eventStore = nil
        reload()
        return true
    }

    /// EventKit says when to reload; the palette adds one refresh per summon.
    private func observeStoreChanges() {
        guard changeObserver == nil, let eventStore else { return }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        changeObserver = NotificationToken(token, center: center)
    }

    /// A Mac asleep through a meeting wakes with a stale snapshot and no edit to trigger a reload.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        wakeObserver = NotificationToken(token, center: center)
    }

    // MARK: - Reading

    /// The per-minute refresh: cheap when the snapshot still holds, which is almost always.
    func reloadIfStale(now: Date) {
        guard let lastReloadAt else {
            reload()
            return
        }
        let aged = now.timeIntervalSince(lastReloadAt) >= Self.staleAfter
        // A day boundary invalidates the span itself, however fresh the snapshot is.
        let rolled = !Calendar.current.isDate(lastReloadAt, inSameDayAs: now)
        guard aged || rolled else { return }
        reload()
    }

    /// `EKEventStore` is not `Sendable`, so this stays on main; only pure values leave.
    func reload() {
        defer { refreshDetails() }
        refreshAccess()
        guard access == .granted else {
            publish([])
            return
        }
        let store = eventStore ?? EKEventStore()
        eventStore = store
        observeStoreChanges()
        lastReloadAt = Date()

        let sources = store.calendars(for: .event)
        calendars =
            sources
            .map {
                MeetingCalendar(
                    id: $0.calendarIdentifier, title: $0.title, accountName: $0.source.title)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let selected = sources.filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty,
            let interval = span.interval(from: Date(), calendar: .current)
        else {
            publish([])
            return
        }
        // The predicate expands recurrence itself; rolling our own never works.
        let predicate = store.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: selected)
        publish(store.events(matching: predicate).compactMap(Self.meeting(from:)))
    }

    private func publish(_ next: [MeetingEvent]) {
        guard next != events else { return }
        events = next
        onChange?()
    }

    private static func meeting(from event: EKEvent) -> MeetingEvent? {
        // A cancelled event is not happening, so it never reaches a surface.
        guard event.status != .canceled, let start = event.startDate, let end = event.endDate,
            let calendar = event.calendar
        else { return nil }
        let me = event.attendees?.first { $0.isCurrentUser }
        return MeetingEvent(
            id: occurrenceID(of: event, start: start),
            title: event.title ?? "(No Title)",
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            isDeclined: me?.participantStatus == .declined,
            calendarID: calendar.calendarIdentifier,
            calendarName: calendar.title,
            calendarColor: color(of: calendar),
            calendarItemID: event.calendarItemIdentifier,
            link: MeetingLink.detect(
                fields: [event.url?.absoluteString, event.location, event.notes],
                account: accountEmail(of: me ?? event.organizer)))
    }

    private static func occurrenceID(of event: EKEvent, start: Date) -> MeetingEvent.ID {
        (event.eventIdentifier ?? event.calendarItemIdentifier)
            + "|\(start.timeIntervalSinceReferenceDate)"
    }

    private static func color(of calendar: EKCalendar) -> MeetingEvent.CalendarColor? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let components = calendar.cgColor?.converted(
                to: space, intent: .defaultIntent, options: nil)?.components,
            components.count >= 3
        else { return nil }
        return MeetingEvent.CalendarColor(
            red: components[0], green: components[1], blue: components[2])
    }

    /// The organizer covers an event booked with no guests and so no attendee list.
    private static func accountEmail(of participant: EKParticipant?) -> String? {
        guard let participant else { return nil }
        return MeetingLink.accountAddress(
            of: participant.url, isCurrentUser: participant.isCurrentUser)
    }

    func event(id: String) -> MeetingEvent? {
        events.first { $0.id == id }
    }

    // MARK: - Details

    func loadDetails(of meeting: MeetingEvent) {
        let next = fetchDetails(of: meeting)
        if next != details { details = next }
    }

    func clearDetails() {
        if details != nil { details = nil }
    }

    private func refreshDetails() {
        guard let shown = details?.meetingID else { return }
        let next = event(id: shown).flatMap(fetchDetails(of:))
        if next != details { details = next }
    }

    /// Only this occurrence's window is queried, so an open page costs one tiny fetch per reload.
    private func fetchDetails(of meeting: MeetingEvent) -> MeetingDetails? {
        guard let eventStore, let calendar = eventStore.calendar(withIdentifier: meeting.calendarID)
        else { return nil }
        // Padded, or a zero-length event would fall outside its own window.
        let predicate = eventStore.predicateForEvents(
            withStart: meeting.start, end: meeting.end.addingTimeInterval(1), calendars: [calendar])
        let match = eventStore.events(matching: predicate).first { event in
            event.startDate.map { Self.occurrenceID(of: event, start: $0) } == meeting.id
        }
        guard let match else { return nil }
        return MeetingDetails(
            meetingID: meeting.id, location: match.location, notes: match.notes,
            attendees: Self.attendees(of: match))
    }

    private static func attendees(of event: EKEvent) -> [MeetingDetails.Attendee] {
        let organizer = event.organizer?.url
        return (event.attendees ?? []).compactMap { participant in
            guard let name = participant.name ?? MeetingLink.address(of: participant.url) else {
                return nil
            }
            return MeetingDetails.Attendee(
                name: name, response: response(to: participant.participantStatus),
                isOrganizer: participant.url == organizer)
        }
    }

    private static func response(
        to status: EKParticipantStatus
    ) -> MeetingDetails.Attendee.Response {
        switch status {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        default: .pending
        }
    }

    /// False means there is no such calendar, which is a report, not a silent no-op.
    func createEvent(_ draft: EventDraft, now: Date) -> Bool {
        let store = eventStore ?? EKEventStore()
        eventStore = store
        guard access == .granted, let calendar = store.defaultCalendarForNewEvents else {
            return false
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.trimmedTitle
        event.startDate = draft.start(from: now)
        event.endDate = draft.end(from: now)
        guard (try? store.save(event, span: .thisEvent, commit: true)) != nil else { return false }
        reload()
        return true
    }

    // MARK: - Per-calendar switches

    func isEnabled(_ calendar: MeetingCalendar) -> Bool {
        !hiddenCalendarIDs.contains(calendar.id)
    }

    func setEnabled(_ enabled: Bool, for calendar: MeetingCalendar) {
        if enabled {
            hiddenCalendarIDs.remove(calendar.id)
        } else {
            hiddenCalendarIDs.insert(calendar.id)
        }
        defaults.set(Array(hiddenCalendarIDs), forKey: hiddenKey)
        reload()
    }
}
