# Calendar and meeting join

Four surfaces over the Mac's own calendar: a **join card** at the top of an empty launcher, a
**Join Next Meeting** global shortcut, the **menu bar**, and meetings that **join themselves**.
Around them sit five launcher commands, a `My Schedule` sub-screen, a camera preview, and individual
events as searchable launcher entries.

## Invariants

- **Nothing polls, and there is one timer.** `.EKEventStoreChanged` is the reload signal, held
  through the RAII `NotificationToken`, and `NSWorkspace.didWakeNotification` covers the sleep it
  cannot. `MeetingClock` is the only timer: one tick on the minute boundary, running **while
  something is watching** — the palette, the menu bar, or auto join. With all three off, an idle Mac
  owns no timer at all. `CalendarCoordinator.applyClock` is the one place that decides, and the
  clock's `Task` is stored and cancelled in `stop()` and in an `isolated deinit`.
- **Auto join fires at most once per meeting per launch**, and only for a meeting starting at or
  after the moment the switch was armed. Both are why `AutoJoinPolicy` takes `armedAt` and the
  already-joined set rather than reading a clock of its own.
- **The camera settles before the panel opens, and stops after it closes.**
  `CameraPreviewSession.start()` resolves access and blocks on `startRunning` first, then hands
  `CameraPreviewController` a settled `Feed` — so the panel's first frame is live video rather than a
  stage it has to swap out, and the TCC prompt never takes key from a panel already up.
  `stop()` runs from the fade-out's completion, so the camera light never outlives the preview but
  is never torn down under a visible one either.
- **The card's window is `[start - lead, min(start + lead, end)]`.** The grace period exists because
  everyone joins late; the `min` is why it never outlives a meeting shorter than the lead.
- **Recurrence comes from `predicateForEvents(withStart:end:calendars:)`**, which expands occurrences
  itself. Masters are never fetched and recurrence is never hand-rolled.
- **`MeetingSpan` narrows the fetch, never the surfaces.** `calendarIncludesTomorrow` reaches
  EventKit through `CalendarStore.span`, so dropping tomorrow shortens the query and every surface
  follows from the one snapshot — no surface filters days out of a snapshot fetched wider. The same
  type owns the wording, so a sentence naming the days can never outlive the query it describes.
- **`UpcomingWindow.agenda` is the only place that says which events count** — timed, not declined,
  not over, in start order. The card, the chord, the menu bar, the schedule and the launcher slice all
  go through it, so they cannot drift apart. Because an event ending changes nothing in EventKit,
  the filter alone is not enough for the launcher slice: `CalendarCoordinator` republishes it on the
  minute boundary and on every summon.
- **The menu bar's `Today` horizon follows the same empty-state rule.** It carries any remaining
  event that starts today, plus an event within 30 minutes after midnight; only then does the title
  mode read `No upcoming events`.
- **`calendarEnabled` doubles as consent**, so it is in `SettingsBackupCoverage.deliberatelyExcluded`
  and only `CalendarCoordinator.setCalendarEnabled` may write it. Tinycast's own dialog comes first,
  the macOS prompt second, and only from the gesture that asked.
- **Per-calendar toggles live on `CalendarStore`, not `AppSettings`.** Calendar identifiers are
  machine-specific, so they are deliberately outside the backup mirror — the same reasoning as
  `palettePosition`.
- **`Model/` stays Foundation-only**; `calendar-test` compiles the shipped sources. EventKit lives in
  `Service/CalendarStore.swift` and nothing EventKit-shaped leaves it.

## The pure layer

`Model/` holds the whole decision, with every clock read injected:

- **`MeetingLink`** — the join link plus its `Provider` and the account whose calendar carried it.
  Ten named services, plus `.generic` for any other `http(s)` link the event carries.
- **`MeetingEvent`** — one occurrence, flattened out of `EKEvent`.
- **`UpcomingWindow`** — `agenda`, `carded`, `joinable` and `countdown`.
- **`MeetingDay`** — the Today / Tomorrow buckets, mirroring the clipboard's `DateBucket`.
- **`MeetingSpan`** — how far ahead the store reads, and the phrasing that names those days.
- **`MenuBarSummary`** — which event the menu bar carries, and for how long.
- **`AutoJoinPolicy`** — whether a meeting should open itself, and which one.
- **`EventDraft`** — what the New Event prompt collects, before anything touches the calendar.

### Finding the link

`MeetingLink.detect(fields:)` is handed `[event.url, event.location, event.notes]` in that order and
scans each for `http(s)` runs. **A named provider anywhere beats a bare link found earlier**, so a
"reset your password" URL at the top of an invite never wins over the Meet link below it.

Link extraction is hand-rolled rather than `NSDataDetector`: a detector is not `Sendable`, and
rebuilding one per event costs more than the scan it replaces. A URL ends at whitespace or a quote,
and trailing punctuation is trimmed, so `(https://whereby.com/acme).` yields the URL alone.

**A URL on a known host that fails that provider's path rule is rejected outright, not demoted to
`.generic`** — `zoom.us/download` sits in half the invites people are sent, and `meet.google.com/tel/…`
is a dial-in helper rather than a meeting.

### Opening it

`MeetingLauncher.join` prefers the desktop app: `MeetingLink.appURL` rewrites a Zoom link to
`zoommtg://zoom.us/join?confno=…` (carrying `pwd` when present) and a `teams.microsoft.com` link to
`msteams:` plus its path and query. Nothing else is rewritten — the rest of the table has no
unambiguous scheme, and guessing one would open the wrong thing. If no app claims the scheme, the
plain `https` link opens instead.

**A Google Meet link opens as the account whose calendar carried it.** Someone signed into several
Google accounts otherwise lands on the account chooser, so `MeetingLink.webURL` appends
`?authuser=<address>` — the address the current user carries in the invite, taken from their attendee
entry or, for a meeting booked with no guests, from the organizer. A link that already names an
`authuser` was written deliberately and is left alone, and no other provider takes an account in its
URL. **`MeetingLink.url` stays the link as written**: it is what the failure report quotes and what
`Copy Meeting Link` puts on the pasteboard, so a link shared onwards carries no address of ours.

No brand artwork ships with the app, so every named provider draws `video.fill` and the **name**
carries the identity; `.generic` draws `link`.

## The card

The card is `LauncherScreen.Row.meeting`, prepended the way the calculator card is. The two can never
both lead: **the calculator only answers a typed query and the card only an empty one**, which is what
keeps the flat selection index a single-row offset. `LauncherList.LeadCard` is that fact made
structural — one optional card, one selected flag, one activate closure, whichever feature owns it.

The countdown re-renders from `MeetingClock.now`, not from a keystroke, so `in 4 min` becomes
`in 3 min` on the boundary. A partial minute rounds **up** (`in 1 min` at 20 seconds out), and the
first minute past the start reads `now` rather than `0 min ago`.

Like the calculator card, a card appearing while the palette is already open shifts the highlight down
by one row. That is the existing behaviour of the row above it and is left alone.

## The chord

`UpcomingWindow.joinable` is deliberately wider than `carded`, and answers in this order:

1. Whatever the card is showing — so the chord always joins what is on screen.
2. Anything currently running, however long ago it started.
3. The next meeting with a link.

It reads the live clock rather than `MeetingClock`, because a chord fires with the palette closed and
nothing ticking.

## Commands

All five leave the launcher when the feature is off **or** when "Show in launcher" is, through
`CalendarCoordinator.applyEnabled`, the `applyQuicklinksPresence` twin. Their shortcuts, the join
card and the menu bar are unaffected: only launcher search is.

The Calendar settings can limit the individual meeting entries in launcher search to the next 1, 3,
or 5 meetings, or leave them all visible. New installations default to the next 3 meetings so a busy
calendar does not crowd out apps and commands.

For the menu bar, **Keep visible — show time left** leaves a started meeting up until it ends: it
changes from `Now` during the first five minutes to its remaining time. The other choices preserve
the option to hide a current event immediately or after a chosen delay.

| Command | Does | Bindable |
| --- | --- | --- |
| Join Next Meeting | Opens the link for the carded, running, or next meeting. | yes |
| My Schedule | Opens the `.schedule` palette mode. | yes |
| Create Event | Prompts for a title, a start and a duration, and writes the event. | yes |
| Copy Meeting Link | The same meeting's link, to the pasteboard. | no |
| Open in Calendar | Hands the meeting to Calendar.app. | no |

**A command that opens a surface is bindable**; the two that act on the next meeting are reached
through the join card's own ⌘K menu instead, where the meeting they act on is on screen.

A miss reports through the HUD (`Nothing to join right now`), not a dialog: it is transient and there
is nothing to acknowledge.

## Reading the store

`CalendarStore` queries `MeetingSpan.interval(from:calendar:)` — midnight today through midnight one
or two days on, in the Mac's own zone — and re-reads whenever `span` changes under it, but only once
it has read at all, so enabling the feature never fires two queries. **The fetch stays on the main
actor**: a day or two of events is a sub-millisecond query and `EKEventStore` is not `Sendable`, so
pushing it off-main would be a fight with no measurable gain. Both the launch-time load and the
per-summon refresh are deferred into a `Task`, because the first EventKit query pays for its XPC
warm-up and both of those paths are protected.

The `EKEventStore` itself is built on first use, so a Mac with the feature off never loads EventKit.
After a grant the store is dropped and rebuilt — one built before the grant does not see the new
calendars.

`MeetingEvent.id` is the event identifier plus the occurrence's start, because a recurring series
shares one identifier across every instance. `calendarItemID` is kept separately: it is the only
handle `ical://ekevent/…` accepts, and a recurring occurrence opens its series.

A cancelled event never reaches a surface. A declined one is dropped by `agenda`, and an all-day or
already-finished one with it.

## The menu bar

`MenuBarSummary` decides what the menu-bar item carries: the earliest event still inside its window,
which is `[start - lead, start)` for **Automatically** and `[start - lead, min(start + hideAfter, end))`
for the timed options. Because the earliest qualifying event wins, one hiding hands the space to the
next with no extra logic.

**The calendar's item and Tinycast's own item are two independent `MenuBarExtra` scenes**, each
inserted by one preference and reading nothing off the other: `showInMenuBar` on General for
Tinycast's, `calendarMenuBarDisplay` here for the calendar's. Either may be the only one in the menu
bar, both may be, or neither. Dragging the calendar item out writes `.disabled`, which is what the
picker already said — it never touches `showInMenuBar`.

The display choice is **Disabled**, **Meeting Icon**, or **Meeting Title**; the title reads
`title • in X min` and is capped at `MenuBarSummary.titleCap` characters — a hard cap is the only
thing that bounds a menu bar. `CalendarMenuBarLabel` reads the coordinator rather than the stores,
which scopes Observation to the label instead of re-running either scene. It falls back to a calendar
glyph when nothing is due, so the calendar item never disappears out from under the user. In **Meeting
Title** mode, once no event remains today it instead reads `No upcoming events`.

`CalendarMenuBarMenu` lists calendar actions only — `Join <title>` and `Open in Calendar...` for the
displayed event, then `My Schedule` and `Calendar Settings...` — so the two menus never repeat each
other. `Join` is absent for a linkless appointment rather than opening Calendar under a name that
lies. **A bare click never joins**: the menu bar is not a button, and a mis-click there would open a
call.

## Auto join and the preview

`AutoJoinPolicy` answers the meeting the join card is already showing, narrowed by three rules —
`start >= armedAt`, `now >= start`, and not already joined. Reusing `UpcomingWindow.carded` rather
than inventing a second window is what keeps one knob, `joinWindowMinutes`, governing the card, the
chord and auto join alike.

The meeting is marked joined **before** the confirmation is raised, so declining does not re-ask a
minute later.

Every join — the card, the chord, the menu bar, auto join — funnels through
`CalendarCoordinator.join(_:uninvited:)`:

```
join(meeting)
  ├─ no link ────────────► openInCalendar
  ├─ camera preview on ──► CameraPreviewController.present → join, or drop
  ├─ uninvited + confirm ► core.confirm → join, or drop
  └─ otherwise ──────────► MeetingLauncher.join
```

**The preview is itself a confirmation**, so it stands in for one when both are on rather than asking
twice. `CameraPreviewPanel` sits at `.floating`, below a dialog's `.modalPanel`, so a failure report
still lands on top of it.

## Settings

The Calendar pane carries the master switch (routed through the coordinator so the consent gate cannot
be bypassed), the `Include Tomorrow's Events` switch, the `Join Next Meeting` recorder, the
join-window picker, and the per-calendar checkbox list — `LauncherItemsSection`'s shape, including the one `Form` row holding a `LazyVStack`, because a
`Form` realizes every row it is handed.

The hidden-calendar set stores **exclusions**, so a calendar added after the setting was written
defaults to on. Holidays and Birthdays are what people switch off.

`autoJoinMeetings` and `cameraPreview` join `calendarEnabled` in
`SettingsBackupCoverage.deliberatelyExcluded`: one arms the app to open links unattended and the
other turns on the camera, and an import must grant neither. The menu-bar settings carry over
normally, and so does `calendarIncludesTomorrow`: it narrows what is read rather than widening what
can be reached.

Because the span is a setting, the two sentences that name the days — the consent dialog and the
pane's own subtitle — interpolate `MeetingSpan.possessivePhrase` rather than spelling the days out,
and the empty schedule reads `MeetingSpan.orPhrase` off the store that did the query. The `.schedule`
placeholder names no days at all: it is a static `PaletteMode` string, and one that advertised a span
it could not read would be wrong half the time.

`CalendarMenuBarDisplay` and `MenuBarEvents` both put their default at `rawValue == 0`, so an unset
preference lands on `.disabled` and `.today` rather than fighting them. `MenuBarEvents` has no `Never`:
`.disabled` is the one switch that takes the item out of the menu bar, and a second one would only
disagree with it.

The Permissions pane shows calendar access alongside Accessibility, but only ever opens System
Settings: the Calendar pane's own switch is the one place that may prompt.
