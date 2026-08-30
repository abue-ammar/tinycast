// Meeting links, the join and menu-bar windows, auto-join, drafts, buckets and span.
import Foundation

@main
@MainActor
struct CalendarTests {
    static var failures = 0
    static var passes = 0

    /// Injected everywhere a date is built, so no assertion depends on the machine's zone.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func main() {
        providerDetection()
        rejectsNonMeetingPages()
        fieldPrecedence()
        linkScanning()
        appURLRewrites()
        accountPrefill()
        agendaFiltering()
        cardWindow()
        chordFallsBackWiderThanTheCard()
        countdownStrings()
        dayBuckets()
        readSpan()
        menuBarWindow()
        menuBarFiltering()
        menuBarToday()
        menuBarTitles()
        autoJoinFiresOnce()
        autoJoinRespectsArming()
        eventDrafts()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Provider detection

    static func providerDetection() {
        expect(provider("https://us02web.zoom.us/j/8901234567") == .zoom, "a Zoom /j/ link is Zoom")
        expect(provider("https://zoom.us/w/123?pwd=xy") == .zoom, "a Zoom webinar link is Zoom")
        expect(provider("https://acme.zoomgov.com/j/55") == .zoom, "zoomgov is Zoom")
        expect(
            provider("https://meet.google.com/abc-defg-hij") == .googleMeet,
            "a Meet code is Google Meet")
        expect(
            provider("https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm8") == .teams,
            "a Teams meetup-join link is Teams")
        expect(provider("https://teams.live.com/meet/9312") == .teams, "a Teams personal link is Teams")
        expect(provider("https://acme.webex.com/acme/j.php?MTID=m1") == .webex, "a Webex site is Webex")
        expect(provider("https://meet.jit.si/DailyStandup") == .jitsi, "meet.jit.si is Jitsi")
        expect(provider("https://8x8.vc/room") == .jitsi, "8x8.vc is Jitsi")
        expect(provider("https://whereby.com/acme") == .whereby, "whereby.com is Whereby")
        expect(provider("https://chime.aws/1234567890") == .chime, "chime.aws is Amazon Chime")
        expect(
            provider("https://global.gotomeeting.com/join/123456789") == .gotoMeeting,
            "gotomeeting.com is GoTo Meeting")
        expect(provider("https://app.goto.com/meeting/xy") == .gotoMeeting, "app.goto.com is GoTo")
        expect(provider("https://bluejeans.com/123456") == .blueJeans, "bluejeans.com is BlueJeans")
        expect(provider("https://join.skype.com/abcdef") == .skype, "join.skype.com is Skype")
        expect(
            provider("https://example.com/rooms/standup") == .generic,
            "an unknown host is still a joinable link")
        expect(MeetingLink.detect(in: "no links here at all") == nil, "plain prose has no link")
        expect(
            MeetingLink.detect(in: "mailto:someone@example.com") == nil,
            "a mailto address is not a join link")
    }

    static func rejectsNonMeetingPages() {
        expect(
            MeetingLink.detect(in: "https://zoom.us/download") == nil,
            "a Zoom download page is not a meeting, and does not fall back to a bare link")
        expect(
            MeetingLink.detect(in: "https://meet.google.com/tel/123") == nil,
            "a Meet dial-in helper is not a meeting")
        expect(
            MeetingLink.detect(in: "https://teams.microsoft.com/downloads") == nil,
            "a Teams download page is not a meeting")
        expect(
            MeetingLink.detect(in: "Join: https://zoom.us/download or https://zoom.us/j/42")?.provider
                == .zoom,
            "a rejected page does not stop the real link being found")
    }

    // MARK: - Where the link comes from

    static func fieldPrecedence() {
        let link = MeetingLink.detect(fields: [
            "https://example.com/first", "https://meet.google.com/abc-defg-hij"
        ])
        expect(link?.provider == .googleMeet, "a named provider beats a bare link found earlier")
        let bare = MeetingLink.detect(fields: [nil, "https://example.com/room", "https://other.test/x"])
        expect(
            bare?.url.absoluteString == "https://example.com/room",
            "with no named provider the earliest bare link wins")
        expect(MeetingLink.detect(fields: [nil, nil]) == nil, "empty fields yield no link")
    }

    static func linkScanning() {
        expect(
            MeetingLink.detect(in: "Dial in (https://whereby.com/acme).")?.url.absoluteString
                == "https://whereby.com/acme",
            "trailing punctuation is not part of the URL")
        expect(
            MeetingLink.detect(in: "<a href=\"https://whereby.com/acme\">join</a>")?.url
                .absoluteString == "https://whereby.com/acme",
            "a quoted href yields the URL alone")
        expect(
            MeetingLink.detect(in: "line one\nhttps://whereby.com/acme\nline three")?.url
                .absoluteString == "https://whereby.com/acme",
            "a newline ends the URL")
        expect(
            MeetingLink.detect(in: "HTTPS://WHEREBY.COM/Acme")?.provider == .whereby,
            "the scheme and host match case-insensitively")
    }

    static func appURLRewrites() {
        expect(
            link("https://us02web.zoom.us/j/8901234567")?.appURL?.absoluteString
                == "zoommtg://zoom.us/join?confno=8901234567",
            "a Zoom link rewrites to the desktop app")
        expect(
            link("https://us02web.zoom.us/j/89?pwd=SeCrEt")?.appURL?.absoluteString
                == "zoommtg://zoom.us/join?confno=89&pwd=SeCrEt",
            "the Zoom passcode travels with the rewrite")
        expect(
            link("https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm8?x=1")?.appURL?
                .absoluteString == "msteams:/l/meetup-join/19%3ameeting_Zm8?x=1",
            "a Teams link rewrites to msteams:, path and query intact")
        expect(
            link("https://meet.google.com/abc-defg-hij")?.appURL == nil,
            "a provider with no unambiguous scheme opens the web instead")
        expect(link("https://example.com/room")?.appURL == nil, "a bare link opens the web")
    }

    static func accountPrefill() {
        expect(
            hosted("https://meet.google.com/abc-defg-hij", "user@domain.com")?.webURL.absoluteString
                == "https://meet.google.com/abc-defg-hij?authuser=user@domain.com",
            "a Meet link opens as the account whose calendar carried it")
        expect(
            hosted("https://meet.google.com/abc?hs=1", "user@domain.com")?.webURL.absoluteString
                == "https://meet.google.com/abc?hs=1&authuser=user@domain.com",
            "the account joins a query the invite already had")
        expect(
            hosted("https://meet.google.com/abc?authuser=1", "user@domain.com")?.webURL
                .absoluteString == "https://meet.google.com/abc?authuser=1",
            "a link naming its own account is left alone")
        expect(
            hosted("https://meet.google.com/abc", "a+b@domain.com")?.webURL.absoluteString
                == "https://meet.google.com/abc?authuser=a%2Bb@domain.com",
            "a plus in the address is encoded, so it cannot be read as a space")
        expect(
            hosted("https://us02web.zoom.us/j/89", "user@domain.com")?.webURL.absoluteString
                == "https://us02web.zoom.us/j/89",
            "no other provider takes an account in the URL")
        expect(
            hosted("https://meet.google.com/abc-defg-hij", nil)?.webURL.absoluteString
                == "https://meet.google.com/abc-defg-hij",
            "a calendar with no address of its own leaves the link as written")
        expect(
            hosted("https://meet.google.com/abc-defg-hij", "user@domain.com")?.url.absoluteString
                == "https://meet.google.com/abc-defg-hij",
            "the link as written is what Copy Meeting Link keeps")
    }

    // MARK: - The join window

    static func agendaFiltering() {
        let events = [
            event(id: "late", start: 60), event(id: "early", start: 0),
            event(id: "allday", start: 30, isAllDay: true),
            event(id: "declined", start: 30, isDeclined: true)
        ]
        let agenda = UpcomingWindow.agenda(from: events, now: at(0))
        expect(agenda.map(\.id) == ["early", "late"], "the agenda is timed, accepted and in start order")

        let over = event(id: "over", start: 0, minutes: 30)
        expect(
            UpcomingWindow.agenda(from: [over], now: at(30)).isEmpty,
            "a meeting is off the agenda the moment it ends, the way it leaves the menu bar")
        expect(
            UpcomingWindow.agenda(from: [over], now: at(29)).map(\.id) == ["over"],
            "one still running stays, however long ago it started")
    }

    static func cardWindow() {
        let window = UpcomingWindow(leadMinutes: 5)
        let meeting = event(id: "standup", start: 60, minutes: 30)
        let start = at(60)
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(-300))?.id == "standup",
            "the card appears exactly five minutes out")
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(-301)) == nil,
            "one second earlier it is not there yet")
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(299))?.id == "standup",
            "it survives almost five minutes past the start, because everyone joins late")
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(300)) == nil,
            "the grace period ends five minutes past the start")

        let brief = event(id: "brief", start: 60, minutes: 3)
        expect(
            window.carded(from: [brief], now: at(60).addingTimeInterval(179))?.id == "brief",
            "a three-minute meeting is carded until it ends")
        expect(
            window.carded(from: [brief], now: at(60).addingTimeInterval(180)) == nil,
            "the grace period never outlives the meeting")

        let linkless = event(id: "linkless", start: 60, link: nil)
        expect(
            window.carded(from: [linkless], now: start) == nil,
            "a meeting with no link is never carded")
        expect(
            UpcomingWindow.agenda(from: [linkless], now: start).map(\.id) == ["linkless"],
            "but it stays on the agenda, so it is still listed and searchable")
    }

    static func chordFallsBackWiderThanTheCard() {
        let window = UpcomingWindow(leadMinutes: 5)
        let running = event(id: "running", start: 0, minutes: 60)
        let next = event(id: "next", start: 120)
        let now = at(0).addingTimeInterval(1800)

        expect(window.carded(from: [running], now: now) == nil, "half an hour in, the card is gone")
        expect(
            window.joinable(from: [running], now: now)?.id == "running",
            "the chord still joins the call that is running")
        expect(
            window.joinable(from: [next], now: now)?.id == "next",
            "with nothing running it offers the next one")
        expect(
            window.joinable(from: [running, next], now: at(120).addingTimeInterval(-120))?.id
                == "next",
            "inside the card window the chord joins what is on screen")
        expect(
            window.joinable(from: [], now: now) == nil, "an empty day offers nothing to join")
        expect(
            window.joinable(from: [event(id: "past", start: -120)], now: now) == nil,
            "a meeting that is over is not offered")
    }

    static func countdownStrings() {
        let start = at(60)
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-240)) == "in 4 min",
            "four minutes out reads as in 4 min")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-60)) == "in 1 min",
            "one minute out reads as in 1 min")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-1)) == "in 1 min",
            "a partial minute rounds up rather than reading as now")
        expect(UpcomingWindow.countdown(to: start, now: start) == "Now", "the start reads as Now")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(299)) == "Now",
            "the first five minutes after the start still read as Now")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(301)) == "Now",
            "a started event stays Now outside the menu-bar-specific timer")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-619 * 60)) == "in 10 hr",
            "a long wait rounds to hours")

        let meeting = event(id: "standup", start: 60, minutes: 30)
        expect(
            UpcomingWindow.menuBarCountdown(for: meeting, now: start.addingTimeInterval(299)) == "Now",
            "the menu bar says Now during the first five minutes")
        expect(
            UpcomingWindow.menuBarCountdown(for: meeting, now: start.addingTimeInterval(301))
                == "24 min left",
            "the menu bar switches to time left after five minutes")
    }

    // MARK: - The menu bar

    static let automatic = MenuBarSummary(
        leadMinutes: 5, hideAfterMinutes: nil, linkedOnly: false, hideCurrentAtStart: true)

    static func menuBarWindow() {
        let meeting = event(id: "standup", start: 60, minutes: 30)
        let start = at(60)
        expect(
            automatic.event(from: [meeting], now: start.addingTimeInterval(-300))?.id == "standup",
            "the menu bar picks the event up exactly at the lead time")
        expect(
            automatic.event(from: [meeting], now: start.addingTimeInterval(-301)) == nil,
            "one second earlier it is not there yet")
        expect(
            automatic.event(from: [meeting], now: start.addingTimeInterval(-1))?.id == "standup",
            "it is still there a second before the start")
        expect(
            automatic.event(from: [meeting], now: start) == nil,
            "Automatically clears it exactly at the start")

        let showTimeLeft = MenuBarSummary(leadMinutes: 5, linkedOnly: false)
        expect(
            showTimeLeft.event(from: [meeting], now: start)?.id == "standup",
            "Keep visible leaves the current event available for its time left")

        let lingering = MenuBarSummary(leadMinutes: 5, hideAfterMinutes: 5, linkedOnly: false)
        expect(
            lingering.event(from: [meeting], now: start.addingTimeInterval(299))?.id == "standup",
            "a five-minute grace keeps it up counting past the start")
        expect(
            lingering.event(from: [meeting], now: start.addingTimeInterval(300)) == nil,
            "and clears it when the grace runs out")

        let brief = event(id: "brief", start: 60, minutes: 3)
        expect(
            lingering.event(from: [brief], now: start.addingTimeInterval(180)) == nil,
            "the grace never outlives the meeting")

        let next = event(id: "next", start: 62)
        expect(
            automatic.event(from: [meeting, next], now: start)?.id == "next",
            "when the current one hides, the next inside its lead time takes the space")
    }

    static func menuBarFiltering() {
        let linkless = event(id: "linkless", start: 60, link: nil)
        let linked = event(id: "linked", start: 61)
        let now = at(60).addingTimeInterval(-120)
        expect(
            automatic.event(from: [linkless, linked], now: now)?.id == "linkless",
            "with the filter off an appointment can hold the menu bar")
        let linkedOnly = MenuBarSummary(leadMinutes: 5, hideAfterMinutes: nil, linkedOnly: true)
        expect(
            linkedOnly.event(from: [linkless, linked], now: now)?.id == "linked",
            "Only show events with meetings skips the one there is nothing to join")
        expect(
            linkedOnly.event(from: [linkless], now: now) == nil,
            "and shows nothing when no event has a link")
        expect(
            automatic.event(from: [event(id: "allday", start: 60, isAllDay: true)], now: now) == nil,
            "the menu bar reads the same agenda as everything else, so all-day events are out")
    }

    static func menuBarToday() {
        let summary = MenuBarSummary(
            leadMinutes: nil, hideAfterMinutes: nil, linkedOnly: false, calendar: calendar)
        let morning = date(year: 2026, month: 8, day: 23, hour: 10)
        let laterToday = event(id: "later", starting: date(year: 2026, month: 8, day: 23, hour: 15))
        expect(
            summary.event(from: [laterToday], now: morning)?.id == "later",
            "Today carries an event later on the same day")

        let justBeforeMidnight = date(year: 2026, month: 8, day: 23, hour: 23, minute: 30)
        let midnight = event(id: "midnight", starting: date(year: 2026, month: 8, day: 24, hour: 0))
        expect(
            summary.event(from: [midnight], now: justBeforeMidnight)?.id == "midnight",
            "Today keeps a meeting that starts exactly thirty minutes after midnight")
        expect(
            MenuBarSummary.hasUpcomingEvent(from: [midnight], now: justBeforeMidnight, calendar: calendar),
            "the empty label agrees with the midnight grace")

        let thirtyOneMinutesOut = date(year: 2026, month: 8, day: 23, hour: 23, minute: 29)
        expect(
            summary.event(from: [midnight], now: thirtyOneMinutesOut) == nil,
            "Today does not keep tomorrow's event more than thirty minutes away")
        expect(
            !MenuBarSummary.hasUpcomingEvent(
                from: [midnight], now: thirtyOneMinutesOut, calendar: calendar),
            "the empty label appears once today is over and tomorrow is not imminent")
    }

    static func menuBarTitles() {
        expect(MenuBarSummary.title("Standup") == "Standup", "a short title is untouched")
        let long = String(repeating: "a", count: MenuBarSummary.titleCap + 5)
        let capped = MenuBarSummary.title(long)
        expect(capped.count == MenuBarSummary.titleCap, "a long title is capped")
        expect(capped.hasSuffix("…"), "and says it was cut")
        expect(
            MenuBarSummary.title(String(repeating: "b", count: MenuBarSummary.titleCap))
                == String(repeating: "b", count: MenuBarSummary.titleCap),
            "a title exactly at the cap keeps every character")
    }

    // MARK: - Auto join

    static func autoJoinFiresOnce() {
        let window = UpcomingWindow(leadMinutes: 5)
        let policy = AutoJoinPolicy(armedAt: at(0))
        let meeting = event(id: "standup", start: 60, minutes: 30)
        let start = at(60)

        expect(
            policy.meeting(
                from: [meeting], now: start.addingTimeInterval(-60), window: window,
                joined: []) == nil,
            "auto join never fires early, however close the card is")
        expect(
            policy.meeting(from: [meeting], now: start, window: window, joined: [])?.id == "standup",
            "it fires at the start")
        expect(
            policy.meeting(from: [meeting], now: start, window: window, joined: ["standup"]) == nil,
            "and never twice for the same meeting")
        expect(
            policy.meeting(
                from: [meeting], now: start.addingTimeInterval(299), window: window,
                joined: [])?.id == "standup",
            "a Mac waking inside the window still joins")
        expect(
            policy.meeting(
                from: [meeting], now: start.addingTimeInterval(300), window: window,
                joined: []) == nil,
            "past the window it stays out of the way")
        expect(
            policy.meeting(
                from: [event(id: "linkless", start: 60, link: nil)], now: start,
                window: window, joined: []) == nil,
            "a meeting with no link is never auto joined")
    }

    static func autoJoinRespectsArming() {
        let window = UpcomingWindow(leadMinutes: 5)
        let running = event(id: "running", start: 60, minutes: 60)
        // Armed a minute into a meeting that was already under way.
        let policy = AutoJoinPolicy(armedAt: at(61))
        expect(
            policy.meeting(from: [running], now: at(61), window: window, joined: []) == nil,
            "arming the switch mid-call does not yank you into the call")
        let later = event(id: "later", start: 90)
        expect(
            policy.meeting(from: [running, later], now: at(90), window: window, joined: [])?.id
                == "later",
            "but the next meeting after arming is fair game")
    }

    // MARK: - The event draft

    static func eventDrafts() {
        var draft = EventDraft()
        expect(!draft.isValid, "a blank draft cannot be written")
        draft.title = "   "
        expect(!draft.isValid, "nor one that is only whitespace")
        draft.title = "  Standup  "
        expect(draft.isValid, "a real title is enough")
        expect(draft.trimmedTitle == "Standup", "the title is trimmed on the way out")

        let now = at(0)
        expect(draft.start(from: now) == now, "an offset of zero starts now")
        expect(
            draft.end(from: now) == now.addingTimeInterval(1800), "the default runs thirty minutes")
        draft.startOffsetMinutes = 30
        draft.durationMinutes = 60
        expect(draft.start(from: now) == at(30), "an offset pushes the start out")
        expect(draft.end(from: now) == at(90), "and the duration runs from there")

        expect(EventDraft.label(startOffset: 0) == "Now", "a zero offset reads as Now")
        expect(EventDraft.label(startOffset: 15) == "15 min", "a smaller offset reads in minutes")
        expect(EventDraft.label(duration: 45) == "45 min", "so does a sub-hour duration")
        expect(EventDraft.label(duration: 60) == "1 hr", "an hour reads as an hour")
    }

    // MARK: - Day buckets

    static func dayBuckets() {
        let now = date(year: 2026, month: 8, day: 23, hour: 22)
        expect(
            MeetingDay(for: now.addingTimeInterval(3600), now: now, calendar: calendar) == .today,
            "an hour before midnight is still today")
        expect(
            MeetingDay(for: now.addingTimeInterval(2 * 3600), now: now, calendar: calendar)
                == .tomorrow,
            "an hour past midnight is tomorrow")
        expect(
            MeetingDay(for: now.addingTimeInterval(48 * 3600), now: now, calendar: calendar) == nil,
            "the day after tomorrow has no bucket")
        expect(
            MeetingDay(for: now.addingTimeInterval(-24 * 3600), now: now, calendar: calendar) == nil,
            "yesterday has no bucket")
    }

    // MARK: - The read span

    static func readSpan() {
        let now = date(year: 2026, month: 8, day: 23, hour: 22)
        let midnight = date(year: 2026, month: 8, day: 23, hour: 0)
        expect(
            MeetingSpan(includesTomorrow: false) == .today
                && MeetingSpan(includesTomorrow: true) == .todayAndTomorrow,
            "the setting names the span")
        expect(
            MeetingSpan.today.interval(from: now, calendar: calendar)
                == DateInterval(start: midnight, end: date(year: 2026, month: 8, day: 24, hour: 0)),
            "today alone runs midnight to midnight, from an evening `now`")
        expect(
            MeetingSpan.todayAndTomorrow.interval(from: now, calendar: calendar)
                == DateInterval(start: midnight, end: date(year: 2026, month: 8, day: 25, hour: 0)),
            "tomorrow adds a second day to the same start")
        expect(
            MeetingSpan.today.possessivePhrase == "today's"
                && MeetingSpan.todayAndTomorrow.orPhrase == "today or tomorrow",
            "the wording follows the span")
    }

    // MARK: - Helpers

    static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    static func at(_ minutes: Int) -> Date {
        epoch.addingTimeInterval(TimeInterval(minutes * 60))
    }

    static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func link(_ text: String) -> MeetingLink? { MeetingLink.detect(in: text) }

    static func hosted(_ text: String, _ account: String?) -> MeetingLink? {
        MeetingLink.detect(fields: [text], account: account)
    }

    static func provider(_ text: String) -> MeetingLink.Provider? { link(text)?.provider }

    static func event(
        id: String, start minutes: Int, minutes duration: Int = 30, isAllDay: Bool = false,
        isDeclined: Bool = false, link: MeetingLink? = MeetingLink.detect(in: "https://example.com/x")
    ) -> MeetingEvent {
        MeetingEvent(
            id: id, title: id, start: at(minutes),
            end: at(minutes).addingTimeInterval(TimeInterval(duration * 60)),
            isAllDay: isAllDay, isDeclined: isDeclined, calendarID: "cal", calendarName: "Work",
            calendarItemID: id, link: link)
    }

    static func event(
        id: String, starting start: Date, minutes duration: Int = 30,
        link: MeetingLink? = MeetingLink.detect(in: "https://example.com/x")
    ) -> MeetingEvent {
        MeetingEvent(
            id: id, title: id, start: start,
            end: start.addingTimeInterval(TimeInterval(duration * 60)),
            isAllDay: false, isDeclined: false, calendarID: "cal", calendarName: "Work",
            calendarItemID: id, link: link)
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
