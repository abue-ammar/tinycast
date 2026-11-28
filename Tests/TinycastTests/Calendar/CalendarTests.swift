import Foundation
import Testing

@testable import Tinycast

struct CalendarTests {
    static let locale = Locale(identifier: "en_US")
    static let epoch = Date(timeIntervalSinceReferenceDate: 0)
    static let bareLink = MeetingLink.detect(in: "https://example.com/x")

    static let automatic = MenuBarSummary(
        leadMinutes: 5, hideAfterMinutes: nil, linkedOnly: false, hideCurrentAtStart: true)

    // MARK: Provider detection

    @Test(arguments: [
        ("https://us02web.zoom.us/j/8901234567", MeetingLink.Provider.zoom),
        ("https://zoom.us/w/123?pwd=xy", .zoom),
        ("https://acme.zoomgov.com/j/55", .zoom),
        ("https://meet.google.com/abc-defg-hij", .googleMeet),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm8", .teams),
        ("https://teams.live.com/meet/9312", .teams),
        ("https://acme.webex.com/acme/j.php?MTID=m1", .webex),
        ("https://meet.jit.si/DailyStandup", .jitsi),
        ("https://8x8.vc/room", .jitsi),
        ("https://whereby.com/acme", .whereby),
        ("https://chime.aws/1234567890", .chime),
        ("https://global.gotomeeting.com/join/123456789", .gotoMeeting),
        ("https://app.goto.com/meeting/xy", .gotoMeeting),
        ("https://bluejeans.com/123456", .blueJeans),
        ("https://join.skype.com/abcdef", .skype),
        ("https://telemost.yandex.ru/j/12345678901234", .telemost),
        ("https://telemost.360.yandex.ru/j/12345678901234", .telemost),
        ("https://example.com/rooms/standup", .generic)
    ])
    func aLinkIsAttributedToItsProvider(_ text: String, _ provider: MeetingLink.Provider) {
        #expect(MeetingLink.detect(in: text)?.provider == provider)
    }

    @Test(arguments: [
        "no links here at all", "mailto:someone@example.com",
        "https://zoom.us/download", "https://meet.google.com/tel/123",
        "https://teams.microsoft.com/downloads", "https://telemost.yandex.com/support"
    ])
    func proseAnAddressOrAProvidersOtherPagesAreNoJoinLink(_ text: String) {
        #expect(MeetingLink.detect(in: text) == nil)
    }

    @Test func aRejectedPageDoesNotStopTheRealLinkBeingFound() {
        let link = MeetingLink.detect(in: "Join: https://zoom.us/download or https://zoom.us/j/42")
        #expect(link?.provider == .zoom)
    }

    // MARK: Where the link comes from

    @Test func aNamedProviderBeatsABareLinkFoundEarlier() {
        let link = MeetingLink.detect(fields: ["https://example.com/first", "https://meet.google.com/abc-defg-hij"])
        #expect(link?.provider == .googleMeet)
    }

    @Test func withNoNamedProviderTheEarliestBareLinkWins() {
        let link = MeetingLink.detect(fields: [nil, "https://example.com/room", "https://other.test/x"])
        #expect(link?.url.absoluteString == "https://example.com/room")
    }

    @Test func emptyFieldsYieldNoLink() {
        #expect(MeetingLink.detect(fields: [nil, nil]) == nil)
    }

    @Test func aTelemostLinkInTheNotesBeatsTheCalendarsOwnEventPage() {
        let link = MeetingLink.detect(fields: [
            "https://calendar.yandex.ru/event?event_id=1", nil, "Join https://telemost.yandex.ru/j/12345678901234"
        ])
        #expect(link?.provider == .telemost)
    }

    @Test(arguments: [
        "Dial in (https://whereby.com/acme).",
        "<a href=\"https://whereby.com/acme\">join</a>",
        "line one\nhttps://whereby.com/acme\nline three",
        "line one\r\nhttps://whereby.com/acme\r\nline three"
    ])
    func punctuationQuotesAndLineBreaksEndTheURL(_ text: String) {
        #expect(MeetingLink.detect(in: text)?.url.absoluteString == "https://whereby.com/acme")
    }

    @Test func theSchemeAndHostMatchCaseInsensitively() {
        #expect(MeetingLink.detect(in: "HTTPS://WHEREBY.COM/Acme")?.provider == .whereby)
    }

    // MARK: Opening the link

    @Test(arguments: [
        ("https://us02web.zoom.us/j/8901234567", "zoommtg://zoom.us/join?confno=8901234567"),
        ("https://us02web.zoom.us/j/89?pwd=SeCrEt", "zoommtg://zoom.us/join?confno=89&pwd=SeCrEt"),
        (
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm8?x=1",
            "msteams:/l/meetup-join/19%3ameeting_Zm8?x=1"
        )
    ])
    func aProviderWithAnAppSchemeOpensInItsApp(_ text: String, _ appURL: String) throws {
        let link = try #require(MeetingLink.detect(in: text))
        #expect(link.appURL?.absoluteString == appURL)
    }

    @Test(arguments: ["https://meet.google.com/abc-defg-hij", "https://example.com/room"])
    func aLinkWithNoUnambiguousSchemeOpensOnTheWeb(_ text: String) throws {
        let link = try #require(MeetingLink.detect(in: text))
        #expect(link.appURL == nil)
    }

    @Test(arguments: [
        ("https://meet.google.com/abc-defg-hij", "user@domain.com",
         "https://meet.google.com/abc-defg-hij?authuser=user@domain.com"),
        ("https://meet.google.com/abc?hs=1", "user@domain.com",
         "https://meet.google.com/abc?hs=1&authuser=user@domain.com"),
        ("https://meet.google.com/abc?authuser=1", "user@domain.com", "https://meet.google.com/abc?authuser=1"),
        ("https://meet.google.com/abc", "a+b@domain.com", "https://meet.google.com/abc?authuser=a%2Bb@domain.com"),
        ("https://us02web.zoom.us/j/89", "user@domain.com", "https://us02web.zoom.us/j/89"),
        ("https://meet.google.com/abc-defg-hij", nil, "https://meet.google.com/abc-defg-hij")
    ] as [(String, String?, String)])
    func aMeetLinkOpensAsTheCalendarsAccount(_ text: String, _ account: String?, _ webURL: String) throws {
        let link = try #require(MeetingLink.detect(fields: [text], account: account))
        #expect(link.webURL.absoluteString == webURL)
    }

    @Test func theLinkAsWrittenIsWhatCopyMeetingLinkKeeps() throws {
        let link = try #require(
            MeetingLink.detect(fields: ["https://meet.google.com/abc-defg-hij"], account: "user@domain.com"))
        #expect(link.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test(arguments: [(true, "https://meet.google.com/abc?authuser=user@domain.com"),
                      (false, "https://meet.google.com/abc")])
    func onlyTheCurrentUsersAddressBecomesTheAccount(_ isCurrentUser: Bool, _ webURL: String) throws {
        let account = try Self.address(of: "mailto:user@domain.com", isCurrentUser: isCurrentUser)
        let link = try #require(MeetingLink.detect(fields: ["https://meet.google.com/abc"], account: account))
        #expect(link.webURL.absoluteString == webURL)
    }

    @Test(arguments: [
        ("mailto:user%40domain.com", "user@domain.com"),
        ("mailto:a+b@domain.com", "a+b@domain.com"),
        ("urn:uuid:1F2A", nil)
    ] as [(String, String?)])
    func aParticipantsAddressIsDecodedOnceFromItsMailto(_ url: String, _ address: String?) throws {
        #expect(try Self.address(of: url) == address)
    }

    /// The placeholder is refused by `isCurrentUser`, not by reading the address.
    @Test func aPlaceholderOrganizerAddressIsStillAnAddress() throws {
        #expect(try Self.address(of: "mailto:unknownorganizer@calendar.google.com") != nil)
    }

    // MARK: The join window

    @Test func theAgendaIsTimedAcceptedAndInStartOrder() {
        let events = [
            Self.event("late", start: 60), Self.event("early", start: 0),
            Self.event("allday", start: 30, isAllDay: true),
            Self.event("declined", start: 30, isDeclined: true)
        ]
        #expect(UpcomingWindow.agenda(from: events, now: Self.at(0)).map(\.id) == ["early", "late"])
    }

    @Test func aMeetingLeavesTheAgendaTheMomentItEnds() {
        let over = Self.event("over", start: 0, minutes: 30)
        #expect(UpcomingWindow.agenda(from: [over], now: Self.at(30)).isEmpty)
        #expect(UpcomingWindow.agenda(from: [over], now: Self.at(29)).map(\.id) == ["over"])
    }

    @Test(arguments: [(-300.0, true), (-301, false), (299, true), (300, false)])
    func theCardShowsFromFiveMinutesOutToFiveMinutesIn(_ offset: TimeInterval, _ carded: Bool) {
        let meeting = Self.event("standup", start: 60, minutes: 30)
        let card = UpcomingWindow(leadMinutes: 5).carded(from: [meeting], now: Self.at(60).addingTimeInterval(offset))
        #expect(card?.id == (carded ? "standup" : nil))
    }

    @Test(arguments: [(179.0, true), (180, false)])
    func theGracePeriodNeverOutlivesTheMeeting(_ offset: TimeInterval, _ carded: Bool) {
        let brief = Self.event("brief", start: 60, minutes: 3)
        let card = UpcomingWindow(leadMinutes: 5).carded(from: [brief], now: Self.at(60).addingTimeInterval(offset))
        #expect(card?.id == (carded ? "brief" : nil))
    }

    @Test func aMeetingWithNoLinkIsListedButNeverCarded() {
        let linkless = Self.event("linkless", start: 60, link: nil)
        #expect(UpcomingWindow(leadMinutes: 5).carded(from: [linkless], now: Self.at(60)) == nil)
        #expect(UpcomingWindow.agenda(from: [linkless], now: Self.at(60)).map(\.id) == ["linkless"])
    }

    @Test func theChordJoinsWiderThanTheCard() {
        let window = UpcomingWindow(leadMinutes: 5)
        let running = Self.event("running", start: 0, minutes: 60)
        let next = Self.event("next", start: 120)
        let now = Self.at(0).addingTimeInterval(1800)

        #expect(window.carded(from: [running], now: now) == nil, "half an hour in, the card is gone")
        #expect(window.joinable(from: [running], now: now)?.id == "running", "it joins the running call")
        #expect(window.joinable(from: [next], now: now)?.id == "next", "with nothing running, the next one")
        #expect(
            window.joinable(from: [running, next], now: Self.at(120).addingTimeInterval(-120))?.id == "next",
            "inside the card window it joins what is on screen")
        #expect(window.joinable(from: [], now: now) == nil, "an empty day offers nothing")
        #expect(window.joinable(from: [Self.event("past", start: -120)], now: now) == nil, "nor does the past")
    }

    // MARK: Countdowns

    @Test(arguments: [
        (-60.0 * 60, UpcomingWindow.RowPill(text: "in 60 min", isImminent: true)),
        (-3 * 60 * 60, .init(text: "in 3 hr", isImminent: false)),
        (-18 * 60 * 60, .init(text: "Wed, Sep 23", isImminent: false)),
        (29 * 60, .init(text: "Now", isImminent: true)),
        (30 * 60, nil)
    ] as [(TimeInterval, UpcomingWindow.RowPill?)])
    func aRowPillCountsDownThroughTheDayThenNamesTheDate(
        _ offset: TimeInterval, _ pill: UpcomingWindow.RowPill?
    ) throws {
        let start = try Self.date("2026-09-23T17:00:00Z")
        let meeting = Self.event("review", starting: start, minutes: 30)
        let actual = try UpcomingWindow.rowPill(
            for: meeting, now: start.addingTimeInterval(offset), calendar: Self.calendar(), locale: Self.locale)
        #expect(actual == pill)
    }

    @Test(arguments: [(-40.0 * 60, "in 40 min"), (0, "Now")])
    func insideTheHourACountdownBeatsTheDateAndTheStartReadsAsNow(_ offset: TimeInterval, _ text: String) throws {
        let start = try Self.date("2026-09-23T17:00:00Z")
        let meeting = Self.event("review", starting: start, minutes: 30)
        let pill = try UpcomingWindow.rowPill(
            for: meeting, now: start.addingTimeInterval(offset), calendar: Self.calendar(), locale: Self.locale)
        #expect(pill?.text == text)
    }

    @Test func aMeetingJustPastMidnightStillCountsDown() throws {
        let lateNight = try Self.date("2026-09-23T23:30:00Z")
        let meeting = Self.event("late", starting: lateNight.addingTimeInterval(40 * 60))
        let pill = try UpcomingWindow.rowPill(
            for: meeting, now: lateNight, calendar: Self.calendar(), locale: Self.locale)
        #expect(pill?.text == "in 40 min")
    }

    @Test func theSuppliedLocaleControlsTheUnits() {
        let french = Locale(identifier: "fr_FR")
        let start = Self.at(60)
        let countdown = UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-240), locale: french)
        #expect(countdown == "in 4\u{00a0}min")
        #expect(EventDraft.label(duration: 60, locale: french) == "1\u{202f}h")
    }

    @Test(arguments: [
        (-240.0, "in 4 min"), (-60, "in 1 min"), (-1, "in 1 min"), (0, "Now"), (299, "Now"), (301, "Now"),
        (-619 * 60, "in 10 hr")
    ] as [(TimeInterval, String)])
    func aCountdownRoundsUpToTheMinuteAndStaysNowOnceStarted(_ offset: TimeInterval, _ text: String) {
        let start = Self.at(60)
        let countdown = UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(offset), locale: Self.locale)
        #expect(countdown == text)
    }

    @Test(arguments: [(299.0, "Now"), (301, "24 min left")])
    func theMenuBarSwitchesToTimeLeftFiveMinutesIn(_ offset: TimeInterval, _ text: String) {
        let meeting = Self.event("standup", start: 60, minutes: 30)
        let countdown = UpcomingWindow.menuBarCountdown(
            for: meeting, now: Self.at(60).addingTimeInterval(offset), locale: Self.locale)
        #expect(countdown == text)
    }

    // MARK: The menu bar

    @Test(arguments: [(-300.0, true), (-301, false), (-1, true), (0, false)])
    func automaticallyShowsAnEventFromItsLeadUntilItsStart(_ offset: TimeInterval, _ shown: Bool) {
        let meeting = Self.event("standup", start: 60, minutes: 30)
        let event = Self.automatic.event(from: [meeting], now: Self.at(60).addingTimeInterval(offset))
        #expect(event?.id == (shown ? "standup" : nil))
    }

    @Test func keepVisibleLeavesTheCurrentEventUpForItsTimeLeft() {
        let meeting = Self.event("standup", start: 60, minutes: 30)
        let summary = MenuBarSummary(leadMinutes: 5, linkedOnly: false)
        #expect(summary.event(from: [meeting], now: Self.at(60))?.id == "standup")
    }

    @Test func aGracePeriodKeepsTheEventUpPastItsStart() {
        let lingering = MenuBarSummary(leadMinutes: 5, hideAfterMinutes: 5, linkedOnly: false)
        let meeting = Self.event("standup", start: 60, minutes: 30)
        let brief = Self.event("brief", start: 60, minutes: 3)
        #expect(lingering.event(from: [meeting], now: Self.at(60).addingTimeInterval(299))?.id == "standup")
        #expect(lingering.event(from: [meeting], now: Self.at(60).addingTimeInterval(300)) == nil)
        #expect(lingering.event(from: [brief], now: Self.at(60).addingTimeInterval(180)) == nil)
    }

    @Test func whenTheCurrentEventHidesTheNextInsideItsLeadTakesTheSpace() {
        let events = [Self.event("standup", start: 60, minutes: 30), Self.event("next", start: 62)]
        #expect(Self.automatic.event(from: events, now: Self.at(60))?.id == "next")
    }

    @Test(arguments: [
        ([], "standup"), (["standup"], "next"), (["next"], "standup"), (["standup", "next"], nil)
    ] as [(Set<String>, String?)])
    func dismissingTheDisplayedEventHandsTheSpaceOn(_ dismissed: Set<String>, _ shown: String?) {
        let events = [Self.event("standup", start: 60, minutes: 30), Self.event("next", start: 62)]
        let now = Self.at(60).addingTimeInterval(-60)
        #expect(Self.automatic.event(from: events, now: now, dismissed: dismissed)?.id == shown)
    }

    @Test func withNothingBehindADismissedEventTheMenuBarClears() {
        let meeting = Self.event("standup", start: 60, minutes: 30)
        let now = Self.at(60).addingTimeInterval(-60)
        #expect(Self.automatic.event(from: [meeting], now: now, dismissed: ["standup"]) == nil)
    }

    @Test func aDismissalIsPerOccurrence() {
        let events = [Self.event("standup", start: 60, minutes: 30), Self.event("next", start: 62)]
        let now = Self.at(62).addingTimeInterval(-60)
        #expect(Self.automatic.event(from: events, now: now, dismissed: ["standup"])?.id == "next")
    }

    @Test func onlyEventsWithMeetingsSkipsAnAppointment() {
        let linkless = Self.event("linkless", start: 60, link: nil)
        let linked = Self.event("linked", start: 61)
        let now = Self.at(60).addingTimeInterval(-120)
        let linkedOnly = MenuBarSummary(leadMinutes: 5, hideAfterMinutes: nil, linkedOnly: true)

        #expect(Self.automatic.event(from: [linkless, linked], now: now)?.id == "linkless", "filter off")
        #expect(linkedOnly.event(from: [linkless, linked], now: now)?.id == "linked")
        #expect(linkedOnly.event(from: [linkless], now: now) == nil)
    }

    @Test func theMenuBarReadsTheAgendaSoAllDayEventsAreOut() {
        let allDay = Self.event("allday", start: 60, isAllDay: true)
        #expect(Self.automatic.event(from: [allDay], now: Self.at(60).addingTimeInterval(-120)) == nil)
    }

    @Test func todayCarriesAnEventLaterTheSameDay() throws {
        let summary = try MenuBarSummary(
            leadMinutes: nil, hideAfterMinutes: nil, linkedOnly: false, calendar: Self.calendar())
        let later = try Self.event("later", starting: Self.date("2026-08-23T15:00:00Z"))
        #expect(try summary.event(from: [later], now: Self.date("2026-08-23T10:00:00Z"))?.id == "later")
    }

    @Test(arguments: [("2026-08-23T23:30:00Z", true), ("2026-08-23T23:29:00Z", false)])
    func todayKeepsTomorrowsEventOnlyThirtyMinutesOut(_ now: String, _ kept: Bool) throws {
        let calendar = try Self.calendar()
        let summary = MenuBarSummary(leadMinutes: nil, hideAfterMinutes: nil, linkedOnly: false, calendar: calendar)
        let midnight = try Self.event("midnight", starting: Self.date("2026-08-24T00:00:00Z"))
        let now = try Self.date(now)
        #expect(summary.event(from: [midnight], now: now)?.id == (kept ? "midnight" : nil))
        #expect(MenuBarSummary.hasUpcomingEvent(from: [midnight], now: now, calendar: calendar) == kept)
    }

    @Test func aLongTitleIsCappedAndSaysSo() {
        #expect(MenuBarSummary.title("Standup") == "Standup")
        let capped = MenuBarSummary.title(String(repeating: "a", count: MenuBarSummary.titleCap + 5))
        #expect(capped.count == MenuBarSummary.titleCap)
        #expect(capped.hasSuffix("…"))
        let atCap = String(repeating: "b", count: MenuBarSummary.titleCap)
        #expect(MenuBarSummary.title(atCap) == atCap)
    }

    // MARK: Auto join

    @Test(arguments: [
        (-60.0, [], nil), (0, [], "standup"), (0, ["standup"], nil), (299, [], "standup"), (300, [], nil)
    ] as [(TimeInterval, Set<String>, String?)])
    func autoJoinFiresOnceFromTheStartUntilTheGraceEnds(
        _ offset: TimeInterval, _ joined: Set<String>, _ fired: String?
    ) {
        let policy = AutoJoinPolicy(armedAt: Self.at(0), namedProvidersOnly: false)
        let meeting = policy.meeting(
            from: [Self.event("standup", start: 60, minutes: 30)], now: Self.at(60).addingTimeInterval(offset),
            window: UpcomingWindow(leadMinutes: 5), joined: joined)
        #expect(meeting?.id == fired)
    }

    @Test func aMeetingWithNoLinkIsNeverAutoJoined() {
        let policy = AutoJoinPolicy(armedAt: Self.at(0), namedProvidersOnly: false)
        let meeting = policy.meeting(
            from: [Self.event("linkless", start: 60, link: nil)], now: Self.at(60),
            window: UpcomingWindow(leadMinutes: 5), joined: [])
        #expect(meeting == nil)
    }

    @Test func armingMidCallWaitsForTheNextMeeting() {
        let window = UpcomingWindow(leadMinutes: 5)
        let running = Self.event("running", start: 60, minutes: 60)
        let policy = AutoJoinPolicy(armedAt: Self.at(61), namedProvidersOnly: false)
        #expect(policy.meeting(from: [running], now: Self.at(61), window: window, joined: []) == nil)
        let later = Self.event("later", start: 90)
        #expect(policy.meeting(from: [running, later], now: Self.at(90), window: window, joined: [])?.id == "later")
    }

    @Test func namedProvidersOnlyLeavesABareLinkToTheCard() {
        let window = UpcomingWindow(leadMinutes: 5)
        let placeholder = Self.event("placeholder", start: 60)
        let call = Self.event("call", start: 60, link: MeetingLink.detect(in: "https://zoom.us/j/8901234567"))
        let anyLink = AutoJoinPolicy(armedAt: Self.at(0), namedProvidersOnly: false)
        let namedOnly = AutoJoinPolicy(armedAt: Self.at(0), namedProvidersOnly: true)

        #expect(anyLink.meeting(from: [placeholder], now: Self.at(60), window: window, joined: [])?.id == "placeholder")
        #expect(namedOnly.meeting(from: [placeholder], now: Self.at(60), window: window, joined: []) == nil)
        let earlier = Self.event("earlier", start: 58)
        #expect(
            namedOnly.meeting(from: [earlier, call], now: Self.at(60), window: window, joined: [])?.id == "call",
            "a bare link the card would pick first does not shadow a call beside it")
    }

    // MARK: The event draft

    @Test func aBlankOrWhitespaceDraftCannotBeWritten() {
        var draft = EventDraft()
        #expect(!draft.isValid)
        draft.title = "   "
        #expect(!draft.isValid)
    }

    @Test func aRealTitleIsEnoughAndIsTrimmed() {
        var draft = EventDraft()
        draft.title = "  Standup  "
        #expect(draft.isValid)
        #expect(draft.trimmedTitle == "Standup")
    }

    @Test func aNewDraftStartsNowForThirtyMinutes() {
        let draft = EventDraft()
        #expect(draft.start(from: Self.at(0)) == Self.at(0))
        #expect(draft.end(from: Self.at(0)) == Self.at(30))
    }

    @Test func anOffsetMovesTheStartAndTheDurationRunsFromThere() {
        var draft = EventDraft()
        draft.startOffsetMinutes = 30
        draft.durationMinutes = 60
        #expect(draft.start(from: Self.at(0)) == Self.at(30))
        #expect(draft.end(from: Self.at(0)) == Self.at(90))
    }

    @Test func draftLabelsReadAsNowMinutesOrHours() {
        #expect(EventDraft.label(startOffset: 0, locale: Self.locale) == "Now")
        #expect(EventDraft.label(startOffset: 15, locale: Self.locale) == "15 min")
        #expect(EventDraft.label(duration: 45, locale: Self.locale) == "45 min")
        #expect(EventDraft.label(duration: 60, locale: Self.locale) == "1 hr")
    }

    @MainActor
    @Test func theEditorOpensOnABlankThirtyMinuteDraftAtTheTitle() {
        let editor = EventEditorSession()
        #expect(!editor.draft.isValid)
        #expect(editor.draft.startOffsetMinutes == 0)
        #expect(editor.draft.durationMinutes == 30)
        #expect(editor.focusedField == .title)
    }

    @MainActor
    @Test func tabCyclesTheFormBothWays() {
        let editor = EventEditorSession()
        var forwards: [EventEditorSession.Field] = []
        for _ in 0..<3 {
            editor.advanceFocus(backwards: false)
            forwards.append(editor.focusedField)
        }
        #expect(forwards == [.start, .duration, .title])

        var backwards: [EventEditorSession.Field] = []
        for _ in 0..<3 {
            editor.advanceFocus(backwards: true)
            backwards.append(editor.focusedField)
        }
        #expect(backwards == [.duration, .start, .title])
    }

    @MainActor
    @Test func theEditorKeepsUnicodeTitlesAndTimesFromSaving() {
        let editor = EventEditorSession()
        editor.draft.title = " \n "
        #expect(!editor.draft.isValid, "a whitespace-only title cannot create an event")
        editor.draft.title = "  Réunion 🎉  "
        editor.draft.startOffsetMinutes = 15
        editor.draft.durationMinutes = 45
        #expect(editor.draft.trimmedTitle == "Réunion 🎉")
        #expect(editor.draft.start(from: Self.at(10)) == Self.at(25))
        #expect(editor.draft.end(from: Self.at(10)) == Self.at(70))
    }

    // MARK: Meeting details

    @Test(arguments: [
        ("  Agenda\n\nBring numbers  ", "Agenda\n\nBring numbers"),
        (" \n ", nil),
        (
            "Join <https://teams.microsoft.com/l/meetup-join/1> now",
            "Join <https://teams.microsoft.com/l/meetup-join/1> now"
        ),
        ("a < b and c > d", "a < b and c > d"),
        ("<b>Agenda</b><br>Q&amp;A<br/><br><br>Wrap&nbsp;up", "Agenda\nQ&A\n\nWrap up"),
        ("<ul><li>One</li><li>Two</li></ul>", "• One\n• Two"),
        ("<p>See <a href=\"https://example.com\">https://example.com</a></p>", "See https://example.com"),
        ("&amp;lt;b&amp;gt; <br>", "&lt;b&gt;")
    ] as [(String, String?)])
    func notesReadAsTrimmedPlainText(_ notes: String, _ text: String?) {
        #expect(MeetingDetails.plainText(fromNotes: notes) == text)
    }

    @Test func theOrganizerLeadsAndABlankLocationIsNone() {
        let organizer = MeetingDetails.Attendee(name: "Ana", response: .accepted, isOrganizer: true)
        let guest = MeetingDetails.Attendee(name: "Ben", response: .pending, isOrganizer: false)
        let other = MeetingDetails.Attendee(name: "Cy", response: .declined, isOrganizer: false)
        let details = MeetingDetails(
            meetingID: "m", location: "  \n", notes: nil, attendees: [guest, organizer, other])
        #expect(details.attendees == [organizer, guest, other])
        #expect(details.location == nil)
    }

    // MARK: Days

    @Test(arguments: [(1.0, 0), (2, 1)])
    func midnightDividesTodayFromTomorrow(_ hours: Double, _ offset: Int) throws {
        #expect(try Self.day(hoursFromTenPM: hours).offset == offset)
    }

    @Test func theDayAfterTomorrowIsKeyedByItsMidnight() throws {
        let day = try Self.day(hoursFromTenPM: 48)
        #expect(day.offset == 2)
        #expect(try day.start == Self.date("2026-08-25T00:00:00Z"))
    }

    @Test func aMeetingRunningFromYesterdayIsHappeningToday() throws {
        #expect(try Self.day(hoursFromTenPM: -24) == Self.day(hoursFromTenPM: 1))
    }

    @Test(arguments: [(1.0, "Today, Aug 23"), (2, "Tomorrow, Aug 24"), (48, "Tuesday, Aug 25")])
    func aDayIsNamedRelativeToTodayThenByWeekdayAlwaysDated(_ hours: Double, _ title: String) throws {
        #expect(try Self.day(hoursFromTenPM: hours).title(calendar: Self.calendar()) == title)
    }

    @Test func meetingsGroupByDayInStartOrder() throws {
        let agenda = [
            Self.event("standup", start: 10 * 60), Self.event("review", start: 14 * 60),
            Self.event("kickoff", start: 33 * 60), Self.event("offsite", start: 81 * 60)
        ]
        let groups = try MeetingDayGroup.grouping(agenda, now: Self.at(9 * 60), calendar: Self.calendar())
        #expect(groups.map(\.day.offset) == [0, 1, 3])
        #expect(groups.map { $0.meetings.map(\.id) } == [["standup", "review"], ["kickoff"], ["offsite"]])
    }

    @Test func anEmptyAgendaHasNoDays() throws {
        #expect(try MeetingDayGroup.grouping([], now: Self.at(9 * 60), calendar: Self.calendar()).isEmpty)
    }

    @Test(arguments: [
        (MeetingSpan.today, "2026-08-24T00:00:00Z"), (.todayAndTomorrow, "2026-08-25T00:00:00Z"),
        (.nextSevenDays, "2026-08-30T00:00:00Z")
    ])
    func aSpanRunsWholeDaysFromTodaysMidnight(_ span: MeetingSpan, _ end: String) throws {
        let interval = try span.interval(from: Self.date("2026-08-23T22:00:00Z"), calendar: Self.calendar())
        #expect(try interval == DateInterval(start: Self.date("2026-08-23T00:00:00Z"), end: Self.date(end)))
    }

    @Test(arguments: [
        (MeetingSpan.today, "Nothing scheduled today"),
        (.todayAndTomorrow, "Nothing scheduled today or tomorrow"),
        (.nextSevenDays, "Nothing scheduled in the next 7 days")
    ])
    func theEmptyMessageFollowsTheSpan(_ span: MeetingSpan, _ message: String) {
        #expect(span.nothingScheduledMessage == message)
    }

    // MARK: Fixtures

    /// Injected wherever a date is read, so no check depends on the Mac's zone.
    static func calendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        return calendar
    }

    static func at(_ minutes: Int) -> Date {
        epoch.addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func date(_ iso: String) throws -> Date {
        try Date(iso, strategy: .iso8601)
    }

    static func day(hoursFromTenPM hours: Double) throws -> MeetingDay {
        let now = try date("2026-08-23T22:00:00Z")
        return try MeetingDay(for: now.addingTimeInterval(hours * 3600), now: now, calendar: calendar())
    }

    static func address(of url: String, isCurrentUser: Bool = true) throws -> String? {
        try MeetingLink.accountAddress(of: #require(URL(string: url)), isCurrentUser: isCurrentUser)
    }

    static func event(
        _ id: String, start minutes: Int, minutes duration: Int = 30, isAllDay: Bool = false,
        isDeclined: Bool = false, link: MeetingLink? = bareLink
    ) -> MeetingEvent {
        MeetingEvent(
            id: id, title: id, start: at(minutes), end: at(minutes + duration), isAllDay: isAllDay,
            isDeclined: isDeclined, calendarID: "cal", calendarName: "Work", calendarColor: nil,
            calendarItemID: id, link: link)
    }

    static func event(_ id: String, starting start: Date, minutes duration: Int = 30) -> MeetingEvent {
        MeetingEvent(
            id: id, title: id, start: start, end: start.addingTimeInterval(TimeInterval(duration * 60)),
            isAllDay: false, isDeclined: false, calendarID: "cal", calendarName: "Work", calendarColor: nil,
            calendarItemID: id, link: bareLink)
    }
}
