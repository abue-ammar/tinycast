import AppKit
import EventKit

/// Today's and tomorrow's meetings, read from EventKit. See docs/features/calendar.md.
@MainActor
@Observable
final class CalendarStore {
    /// Flattened occurrences over `[startOfToday, endOfTomorrow]`, newest query wins.
    private(set) var events: [MeetingEvent] = []
    private(set) var calendars: [MeetingCalendar] = []
    private(set) var access: CalendarAccess = Permissions.calendarAccess()

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

    /// How long a snapshot is trusted with the palette closed. `.EKEventStoreChanged` covers edits;
    /// this covers the day rolling over and a Mac that slept through both.
    private static let staleAfter: TimeInterval = 10 * 60

    init() {
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    }

    // MARK: - Lifecycle

    func start() {
        access = Permissions.calendarAccess()
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
    }

    /// Tinycast's own consent dialog has already been accepted by the time this runs.
    func requestAccess() async -> Bool {
        let granted = await Permissions.requestCalendarAccess()
        access = Permissions.calendarAccess()
        guard granted else { return false }
        // A store built before the grant never sees the new calendars; drop it and rebuild.
        changeObserver = nil
        eventStore = nil
        reload()
        return true
    }

    /// EventKit says when to reload, so nothing here polls. The palette adds one refresh per summon.
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
        // A day boundary invalidates the two-day span itself, however fresh the snapshot is.
        let rolled = !Calendar.current.isDate(lastReloadAt, inSameDayAs: now)
        guard aged || rolled else { return }
        reload()
    }

    /// Two days of events is a sub-millisecond query and `EKEventStore` is not `Sendable`, so this
    /// stays on the main actor; only pure `MeetingEvent` values leave it.
    func reload() {
        access = Permissions.calendarAccess()
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
        guard !selected.isEmpty, let span = Self.span(from: Date()) else {
            publish([])
            return
        }
        // The predicate expands recurrence itself; fetching masters and rolling our own never works.
        let predicate = store.predicateForEvents(
            withStart: span.start, end: span.end, calendars: selected)
        publish(store.events(matching: predicate).compactMap(Self.meeting(from:)))
    }

    private func publish(_ next: [MeetingEvent]) {
        guard next != events else { return }
        events = next
        onChange?()
    }

    /// Midnight today through midnight the day after tomorrow, in the Mac's own zone.
    private static func span(from now: Date) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .day, for: now)?.start,
            let end = calendar.date(byAdding: .day, value: 2, to: start)
        else { return nil }
        return (start, end)
    }

    private static func meeting(from event: EKEvent) -> MeetingEvent? {
        // A cancelled event is not happening, so it never reaches a surface.
        guard event.status != .canceled, let start = event.startDate, let end = event.endDate,
            let calendar = event.calendar
        else { return nil }
        let declined =
            event.attendees?
            .first { $0.isCurrentUser }?.participantStatus == .declined
        return MeetingEvent(
            id: (event.eventIdentifier ?? event.calendarItemIdentifier)
                + "|\(start.timeIntervalSinceReferenceDate)",
            title: event.title ?? "(No Title)",
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            isDeclined: declined,
            calendarID: calendar.calendarIdentifier,
            calendarName: calendar.title,
            calendarItemID: event.calendarItemIdentifier,
            link: MeetingLink.detect(fields: [
                event.url?.absoluteString, event.location, event.notes
            ]))
    }

    func event(id: String) -> MeetingEvent? {
        events.first { $0.id == id }
    }

    /// Writes the draft to the calendar new events go to. False means there is no such calendar,
    /// which is a report rather than a silent no-op.
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
