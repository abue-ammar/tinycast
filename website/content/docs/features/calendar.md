---
title: Calendar & meetings
description: Join your next meeting with one key, see your day, and show the next event in the menu bar.
---

Tinycast reads the calendars already on your Mac, finds the join link in each meeting, and lets you
join with one keystroke. It works with any calendar account macOS supports, like iCloud, Google or
Exchange.

Turn it on in **Settings → Calendar → Join meetings from Tinycast**. It's **off** by default. When
you turn it on, Tinycast explains what it reads, and then macOS asks for calendar access. See
[Permissions](/docs/permissions#calendars).

Events are read on your Mac and **never leave it**.

## Four ways to join

- **The join card.** When a meeting is about to start, a card with a live countdown appears at the
  top of the launcher. Press <kbd>return</kbd> to join.
- **Join Next Meeting.** A command you can assign a global shortcut. It joins the meeting shown on
  the card, a meeting that's already running, or the next meeting with a link.
- **The menu bar.** An optional calendar item shows your next event, and its menu lists upcoming
  events by day.
- **Auto join.** Meetings can open automatically when they start.

If there's nothing to join, a short message says **Nothing to join right now**.

### The join card

The card appears a set time before a meeting starts and stays for the same amount of time after,
but never past the meeting's end. **Show the meeting card** sets that time: 1, 2, **5** (default),
10 or 15 minutes.

| Action (<kbd>⌘</kbd><kbd>K</kbd>) | Shortcut                      |
| --------------------------------- | ----------------------------- |
| Join Meeting                      | <kbd>return</kbd>             |
| Copy Meeting Link                 | <kbd>⌘</kbd><kbd>return</kbd> |
| Open in Calendar                  | <kbd>⌘</kbd><kbd>O</kbd>      |
| Show Details                      | <kbd>⌘</kbd><kbd>I</kbd>      |

A meeting without a link opens in Calendar instead. If another calendar app is your default,
**Open in Calendar** opens that app.

These actions work the same on every meeting row: the card, the Meetings section in search and My
Schedule.

### Meeting details

**Show Details** opens a page with the meeting's day, time and calendar, its location, the
attendees and their replies, and the description. <kbd>return</kbd>, <kbd>⌘</kbd><kbd>return</kbd>,
<kbd>⌘</kbd><kbd>O</kbd> and <kbd>⌘</kbd><kbd>K</kbd> work on the page the same way they do on the
row.

## Which links it finds

Tinycast checks the event's URL, location and notes, in that order. It recognizes **Zoom**,
**Google Meet**, **Microsoft Teams**, **Webex**, **Jitsi**, **Whereby**, **Amazon Chime**,
**GoTo Meeting**, **BlueJeans** and **Skype**, and falls back to any other web link in the event.

- **A link to a known service always takes priority over a plain link**, so a "reset your password"
  link at the top of an invite never wins over the Meet link below it.
- Links that aren't meetings, like `zoom.us/download` or a Meet dial-in page, are ignored.
- **Zoom and Teams open in their desktop apps** if they're installed, and in the browser otherwise.
  Links open in your default browser, or in the browser you choose in **Open Meeting Links In**.
- **Google Meet opens with the right account.** If you're signed in to several Google accounts, the
  link opens with the account whose calendar has the meeting, instead of the account chooser.
- **Copy Meeting Link** copies the link exactly as it appears in the event.

Declined, canceled, all-day and finished events are always skipped.

## Commands

| Command           | Does                                                                                            |
| ----------------- | ----------------------------------------------------------------------------------------------- |
| Join Next Meeting | Opens the card's meeting, the running one, or the next one                                      |
| My Schedule       | Shows your meetings as a list in the palette                                                    |
| Create Event      | Opens a form for a title, start time and duration, then adds the event to your default calendar |
| Copy Meeting Link | Copies the next meeting's link                                                                  |
| Open in Calendar  | Opens the next meeting in Calendar                                                              |

Each command has a checkbox, a shortcut recorder and an alias field in **Settings → Calendar**.

### Meetings in search

Upcoming meetings also appear in launcher search, in their own **Meetings** section.
**Upcoming meetings in launcher** sets how many: **1 next**, **3 next**, **5 next** (default) or
**All**. **Show in launcher** removes meetings from search. The calendar commands stay, and the join
card, the menu bar item and your shortcuts keep working.

### My Schedule

My Schedule lists your remaining events for the days Tinycast reads, grouped by day. Type to filter.
<kbd>return</kbd> joins the selected meeting, and <kbd>⌘</kbd><kbd>K</kbd> offers the same
actions as the join card.

## How far ahead it reads

**Days to Show** sets how far ahead Tinycast reads: **Today**, **Today and Tomorrow** (default) or
**Next 7 Days**. My Schedule, the menu bar item and launcher search all use this setting.

## Auto join

**Auto Join Meetings** (off by default) opens each meeting when it starts.

- It only joins meetings that start **after** you turned it on.
- It joins each meeting **once**, even if you decline the confirmation.
- **Confirm before joining** (on by default) asks you first.
- **Only join known meeting services** (off by default) skips events whose only link is a plain web
  link, like a booking page or a document. The join card, the menu bar and your shortcut still offer
  those links.

## Camera preview

**Camera Preview** (off by default) shows your camera before you join, so you can check how you look
and what's behind you. <kbd>return</kbd> joins and <kbd>esc</kbd> cancels.

The preview replaces the confirmation, so you're never asked twice. The camera only turns on when
the preview opens and turns off as soon as it closes. It's the same camera screen as
[Open Camera](/docs/features/camera).

## The menu bar

The calendar has its **own** menu bar item, separate from the Tinycast icon. You can show either one,
both or neither.

| Setting                                | Options                                                                  | Default                          |
| -------------------------------------- | ------------------------------------------------------------------------ | -------------------------------- |
| Calendar in Menu Bar                   | Disabled · Meeting Icon · Meeting Title                                  | **Disabled**                     |
| Days to Show                           | Today · Today and Tomorrow · Next 7 Days                                 | **Today and Tomorrow**           |
| Show Upcoming Events                   | Today · 2 · 5 · 10 · 30 minutes before                                   | **Today**                        |
| Only show events with meetings         | On · Off                                                                 | **On**                           |
| Hide when there are no upcoming events | On · Off                                                                 | **Off**                          |
| Hide Current Event                     | Keep visible, show time left · Automatically · After 5, 10 or 30 minutes | **Keep visible, show time left** |

With **Meeting Title**, the item shows something like `Standup • in 4 min`. When there are no more
events today, it shows **No upcoming events**. "Today" includes the first 30 minutes after midnight.

The item's menu has **Join**, **Open in Calendar** and **Dismiss Event**. Below those, it lists your
upcoming events by day, for the days set in **Days to Show**. A filled dot marks the meeting in
progress. Click an event to join it; an event without a meeting link opens in Calendar. The menu ends
with **My Schedule** (<kbd>⌘</kbd><kbd>O</kbd>) and **Calendar Settings…** (<kbd>⌘</kbd><kbd>,</kbd>).
**Clicking the item itself never joins a meeting**, so a stray click in the menu bar can't start a
call.

With **Hide when there are no upcoming events** on, the item leaves the menu bar while it has no
event to show, and comes back when one is due.

Dragging the item out of the menu bar sets it to Disabled.

## Choosing calendars

The **Calendars** list at the bottom of the pane has a search field and a checkbox for each
calendar. Holidays and Birthdays are the ones people usually turn off. Calendars you add later are
on by default.

## Backups

Three settings are never included in [backups](/docs/reference/backup), because each one is a form
of consent: the calendar switch itself, **Auto Join Meetings** and **Camera Preview**. Your calendar
checkboxes and **Open Meeting Links In** also stay on this Mac. Other settings, like the menu bar
options, are backed up as usual.
