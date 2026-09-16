---
title: Calendar & meetings
description: Join the next meeting with one key, see your day, and keep the next event in the menu bar.
---

Tinycast reads the calendars already on your Mac, finds the join link in each meeting, and puts it
one keystroke away. It works with any calendar macOS knows about, like iCloud, Google or Exchange.

**Settings → Calendar → Join meetings from Tinycast** holds the switch. It ships **off**. Turning it
on explains what it reads, then macOS asks for calendar access. See [Permissions](/docs/permissions#calendars).

Events are read on your Mac. **Nothing leaves it.**

## Four ways to join

- **The join card.** When a meeting is about to start, a card sits at the top of the launcher with a
  live countdown. <kbd>return</kbd> joins.
- **Join Next Meeting.** A command you can bind to a global shortcut. It joins what the card shows,
  or a meeting already running, or the next meeting with a link.
- **The menu bar.** An optional calendar item shows the next event and a menu to join it.
- **Auto join.** Meetings can open themselves as they start.

If there is nothing to join, a small message says **Nothing to join right now**.

### The join card

The card shows up a set time before a meeting starts and stays for the same time after, but never
past the meeting's end. **Show the join card** sets that time: 1, 2, **5** (default), 10 or 15 minutes.

| Action (<kbd>⌘</kbd><kbd>K</kbd>) | Shortcut                      |
| --------------------------------- | ----------------------------- |
| Join Meeting                      | <kbd>return</kbd>             |
| Copy Meeting Link                 | <kbd>⌘</kbd><kbd>return</kbd> |
| Open in Calendar                  |                               |

A meeting with no link opens in Calendar instead.

## Which links it finds

Tinycast looks in the event's URL, location and notes, in that order. It knows **Zoom**,
**Google Meet**, **Microsoft Teams**, **Webex**, **Jitsi**, **Whereby**, **Amazon Chime**,
**GoTo Meeting**, **BlueJeans** and **Skype**, and falls back to any other web link in the event.

- **A known service always beats a plain link**, so a "reset your password" link at the top of an
  invite never wins over the Meet link below it.
- Links that are not meetings, like `zoom.us/download` or a Meet dial-in page, are ignored.
- **Zoom and Teams open in their desktop apps** when installed, and in the browser otherwise.
- **Google Meet opens as the right account.** If you are signed in to several Google accounts, the
  link opens as the one whose calendar holds the meeting, not the account chooser.
- **Copy Meeting Link** copies the link exactly as it was written.

Declined, cancelled, all-day and finished events are skipped everywhere.

## Commands

| Command           | Does                                                        |
| ----------------- | ----------------------------------------------------------- |
| Join Next Meeting | Opens the card's meeting, the running one, or the next      |
| My Schedule       | Opens your meetings as a list in the palette                |
| Create Event      | Asks for a title, when it starts and how long, then adds it |
| Copy Meeting Link | Copies the next meeting's link                              |
| Open in Calendar  | Opens the next meeting in Calendar                          |

Each command has a checkbox, a shortcut recorder and an alias field in **Settings → Calendar**.

### Meetings in search

Upcoming meetings also show up in launcher search, in their own **Meetings** section.
**Upcoming meetings in launcher** sets how many: **1 next**, **3 next** (default), **5 next** or
**All**. **Show in launcher** takes the meetings and the calendar commands out of search. The join
card, the menu bar and your shortcuts keep working.

### My Schedule

My Schedule lists what is left of today, and tomorrow when that is included, grouped by day. Type to
filter. <kbd>return</kbd> joins the selected meeting, and <kbd>⌘</kbd><kbd>K</kbd> offers
**Open in Calendar**.

## How far ahead it reads

**Include Tomorrow's Events** (on by default) reads tomorrow as well as the rest of today. Turn it
off and every surface only looks at today.

## Auto join

**Auto Join Meetings** (off by default) opens a meeting as it starts.

- It only joins meetings that start **after** you turned it on.
- It joins each meeting **once**, even if you decline the confirmation.
- **Confirm before joining** (on by default) asks first.

## Camera preview

**Camera Preview** (off by default) shows your camera before you join, so you can check your hair
and your background. <kbd>return</kbd> joins and <kbd>esc</kbd> cancels.

The preview counts as the confirmation, so you are never asked twice. The camera turns on only when
the preview opens and off as soon as it closes. It uses the same camera screen as
[Open Camera](/docs/features/camera).

## The menu bar

The calendar gets its **own** menu bar item, separate from the Tinycast icon. You can show either,
both or neither.

| Setting                                | Options                                                                  | Default                          |
| -------------------------------------- | ------------------------------------------------------------------------ | -------------------------------- |
| Calendar in Menu Bar                   | Disabled · Meeting Icon · Meeting Title                                  | **Disabled**                     |
| Show Upcoming Events                   | Today · 2 · 5 · 10 · 30 minutes before                                   | **Today**                        |
| Only show events with meetings         | On · Off                                                                 | **On**                           |
| Hide the item when nothing is upcoming | On · Off                                                                 | **Off**                          |
| Hide Current Event                     | Keep visible, show time left · Automatically · After 5, 10 or 30 minutes | **Keep visible, show time left** |

**Meeting Title** reads like `Standup • in 4 min`. Once nothing is left today, it reads
**No upcoming events**. Today also counts the first 30 minutes after midnight.

Prefer an empty menu bar to a placeholder? Turn on **Hide the item when nothing is upcoming** and the
item leaves the menu bar whenever it has no event to show, returning when the next one reaches it —
at the lead **Show Upcoming Events** sets. On **Today** it stays up while any event remains today; on
**30 minutes before** it appears half an hour ahead of each meeting and goes between them.

The item's menu offers **Join** the meeting, **Open in Calendar…**, **My Schedule** and
**Calendar Settings…**. **A plain click never joins.** Mis-clicking the menu bar should not open a
call.

Dragging the item out of the menu bar sets it to Disabled.

## Choosing calendars

The **Calendars** list at the bottom of the pane has a checkbox per calendar. Holidays and Birthdays
are the usual ones to switch off. A calendar you add later starts switched on.

## Backups

Three settings stay out of [backups](/docs/reference/backup), because each is a consent: the
calendar switch itself, **Auto Join Meetings** and **Camera Preview**. Your calendar checkboxes stay
on this Mac too. The rest, like the menu bar choices, travel normally.
