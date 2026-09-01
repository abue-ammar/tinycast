import AppKit

/// Owns joining a meeting: the consent gate, the card's and the chord's actions, feature presence.
@MainActor
final class CalendarCoordinator {
    private let store: CalendarStore
    private let clock: MeetingClock
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    /// Dialogs and the HUD, so both stay owned by `AppCore`.
    private unowned let core: AppCore

    /// Its own surface, the way `NotesCoordinator` owns the notes window.
    private lazy var cameraPreview = CameraPreviewController()

    private var paletteVisible = false
    /// When auto join was last armed; a meeting already under way then is never joined.
    private var armedAt = Date.distantFuture
    /// Auto joined this launch, so a meeting opens itself at most once.
    private var autoJoined: Set<MeetingEvent.ID> = []

    init(
        store: CalendarStore,
        clock: MeetingClock,
        appIndex: AppIndex,
        settings: AppSettings,
        paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.store = store
        self.clock = clock
        self.appIndex = appIndex
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// The window every surface reads, so the card, the chord and the schedule cannot disagree.
    var window: UpcomingWindow { UpcomingWindow(leadMinutes: settings.joinWindowMinutes.rawValue) }

    /// The days the store reads, and the wording every sentence that names them uses.
    var span: MeetingSpan { MeetingSpan(includesTomorrow: settings.calendarIncludesTomorrow) }

    /// The meeting the join card shows; `now` comes from the ticking clock.
    var cardedMeeting: MeetingEvent? {
        guard settings.calendarEnabled else { return nil }
        return window.carded(from: store.events, now: clock.now)
    }

    /// Live rather than clock-driven: a chord reads this with nothing ticking.
    var agenda: [MeetingEvent] { UpcomingWindow.agenda(from: store.events, now: Date()) }

    /// The calendar label keeps its plain icon until today's events are exhausted, with a small
    /// grace across midnight for a meeting that starts imminently.
    var hasUpcomingMenuBarEvent: Bool {
        MenuBarSummary.hasUpcomingEvent(from: store.events, now: clock.now)
    }

    /// The event the menu bar carries, or nil for the plain icon.
    var menuBarEvent: MeetingEvent? {
        guard settings.calendarEnabled, settings.calendarMenuBarDisplay != .disabled else {
            return nil
        }
        let summary = MenuBarSummary(
            leadMinutes: settings.menuBarEvents == .today ? nil : settings.menuBarEvents.rawValue,
            hideAfterMinutes: settings.hideCurrentEvent.minutes,
            linkedOnly: settings.menuBarLinkedEventsOnly,
            hideCurrentAtStart: settings.hideCurrentEvent.hidesAtStart)
        return summary.event(from: store.events, now: clock.now)
    }

    // MARK: - Feature switch

    /// The switch funnels here so enabling, which is also consent, confirms first.
    func setCalendarEnabled(_ enabled: Bool) {
        guard enabled != settings.calendarEnabled else { return }
        if !enabled {
            settings.calendarEnabled = false
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable calendar?",
                    message:
                        "Tinycast reads \(span.possessivePhrase) events to find join links. "
                        + "Nothing leaves this Mac.",
                    symbol: "calendar", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }

            settings.calendarEnabled = true
            // The one prompt for this feature, raised from the gesture that asked for it.
            guard await store.requestAccess() else { return }
            applyEnabled()
        }
    }

    /// Publishes or withdraws everything the feature contributes to the launcher.
    func applyEnabled() {
        let enabled = settings.calendarEnabled
        appIndex.setCommandsVisible(
            [.joinNextMeeting, .copyMeetingLink, .mySchedule, .openInCalendar, .createEvent],
            enabled && settings.calendarShowInLauncher)
        guard enabled else {
            store.stop()
            clock.stop()
            publishEntries()
            return
        }
        store.onChange = { [weak self] in self?.publishEntries() }
        clock.onTick = { [weak self] in self?.minuteDidPass() }
        applySpan()
        store.start()
        publishEntries()
        applyClock()
    }

    /// Changing which days are read re-queries EventKit, so it goes through the store.
    func applySpan() {
        store.span = span
    }

    /// The clock runs while something is watching it. With all three off an idle Mac owns no timer.
    func applyClock() {
        armAutoJoin()
        let watched =
            paletteVisible || settings.calendarMenuBarDisplay != .disabled
            || settings.autoJoinMeetings
        guard settings.calendarEnabled, watched else {
            clock.stop()
            return
        }
        clock.start()
    }

    /// Stamped when auto join goes on, so switching it on mid-call cannot yank you into that call.
    private func armAutoJoin() {
        guard settings.calendarEnabled, settings.autoJoinMeetings else {
            armedAt = .distantFuture
            return
        }
        if armedAt == .distantFuture { armedAt = Date() }
    }

    /// An event ending changes nothing in EventKit, so the republish is what drops it.
    private func minuteDidPass() {
        store.reloadIfStale(now: clock.now)
        publishEntries()
        autoJoinIfDue()
    }

    private func autoJoinIfDue() {
        guard settings.calendarEnabled, settings.autoJoinMeetings, !core.isShowingDialog else {
            return
        }
        let policy = AutoJoinPolicy(armedAt: armedAt)
        guard
            let meeting = policy.meeting(
                from: store.events, now: clock.now, window: window, joined: autoJoined)
        else { return }
        // Marked before the ask, so declining a confirmation does not re-ask a minute later.
        autoJoined.insert(meeting.id)
        join(meeting, uninvited: true)
    }

    private func publishEntries() {
        guard settings.calendarEnabled, settings.calendarShowInLauncher else {
            appIndex.setMeetings([])
            return
        }
        let meetings =
            settings.calendarLauncherLimit.maximum.map { Array(agenda.prefix($0)) } ?? agenda
        appIndex.setMeetings(meetings.map(Self.entry(for:)))
    }

    private static func entry(for meeting: MeetingEvent) -> AppEntry {
        AppEntry(
            id: meeting.entryID, name: meeting.title,
            url: URL(
                string: "tinycast://meeting/"
                    + (meeting.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
                        ?? ""))!,
            bundleID: nil, kind: .meeting,
            matchAliases: [meeting.calendarName],
            symbolName: meeting.link?.provider.sfSymbol ?? "calendar")
    }

    // MARK: - Palette lifecycle

    /// Events go stale while the palette is closed, and the countdown ticks only when seen.
    func paletteDidShow() {
        paletteVisible = true
        applyClock()
        guard settings.calendarEnabled else { return }
        // Meetings end while the palette is closed, and with no clock nothing republished them.
        publishEntries()
        // Off the summon path: the card is observation-driven, so it can land a frame later.
        Task { store.reload() }
    }

    func paletteDidHide() {
        paletteVisible = false
        applyClock()
    }

    // MARK: - Commands

    func joinNextMeeting() {
        guard let meeting = nextJoinable() else {
            report("Nothing to join right now")
            return
        }
        join(meeting)
    }

    func copyNextMeetingLink() {
        guard let meeting = nextJoinable() else {
            report("Nothing to join right now")
            return
        }
        copyLink(meeting)
    }

    func createEvent() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        guard settings.calendarEnabled, store.access == .granted else {
            report("Turn Calendar on in Settings first")
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard let draft = await core.createEvent() else { return }
            guard store.createEvent(draft, now: Date()) else {
                _ = await core.reportFailure(
                    title: "Couldn't create the event",
                    message: "No calendar on this Mac accepts new events.",
                    symbol: "calendar.badge.exclamationmark", recovery: nil)
                return
            }
            core.showMessage("Event created")
        }
    }

    func openNextMeetingInCalendar() {
        guard let meeting = window.joinable(from: store.events, now: Date()) ?? agenda.first else {
            report("Nothing scheduled \(span.orPhrase)")
            return
        }
        openInCalendar(meeting)
    }

    /// Live rather than clock-driven: a chord fires without the palette, so nothing is ticking.
    private func nextJoinable() -> MeetingEvent? {
        guard settings.calendarEnabled else { return nil }
        return window.joinable(from: store.events, now: Date())
    }

    // MARK: - Row actions

    /// ↵ on a meeting row: join it, or hand a linkless one to Calendar.
    func activateMeeting(id: String) {
        guard let meeting = store.event(id: id) else { return }
        join(meeting)
    }

    /// `uninvited` marks an auto join, the only case that may have to ask before it acts.
    func join(_ meeting: MeetingEvent, uninvited: Bool = false) {
        guard let link = meeting.link else {
            openInCalendar(meeting)
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await joinAfterGate(meeting, link: link, uninvited: uninvited) }
    }

    /// The camera preview doubles as the auto join confirmation, so there is one surface, not two.
    private func joinAfterGate(
        _ meeting: MeetingEvent, link: MeetingLink, uninvited: Bool
    ) async {
        // The preview is itself a confirmation, so it stands in for one when both are on.
        if settings.cameraPreview {
            guard await cameraPreview.present(meeting: meeting, now: Date()) else { return }
        } else if uninvited, settings.autoJoinConfirms {
            NSApp.activate(ignoringOtherApps: true)
            guard
                await core.confirm(
                    title: "Join \(meeting.title)?",
                    message: UpcomingWindow.countdown(to: meeting.start, now: Date()),
                    symbol: link.provider.sfSymbol, confirmTitle: "Join", tone: .neutral,
                    confirmRole: .standard, dismissTitle: "Not Now")
            else { return }
        }
        if MeetingLauncher.join(link) { return }
        _ = await core.reportFailure(
            title: "Couldn't open the meeting link",
            message: "Nothing on this Mac would open \(link.url.absoluteString).",
            symbol: "video.slash", recovery: nil)
    }

    func copyLink(_ meeting: MeetingEvent) {
        guard let link = meeting.link else {
            report("This meeting has no link")
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(link.url.absoluteString)
        core.showMessage("Meeting link copied")
    }

    func openInCalendar(_ meeting: MeetingEvent) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        MeetingLauncher.showInCalendar(meeting)
    }

    func showSchedule() {
        paletteCoordinator.togglePalette(mode: .schedule)
    }

    /// A miss is transient, so it reports through the HUD rather than a dialog needing dismissal.
    private func report(_ message: String) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.showMessage(message, tone: .neutral)
    }
}
