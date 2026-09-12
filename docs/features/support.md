# Support

One window, one checkout link, and a checkbox deciding whether it may ever reopen itself. Every other
surface — the website's hero and footer, the docs sidebar, the README badge — is a bare link to the
same URL, so `SupportCoordinator.checkout` is the only place the destination is written down.

## Invariants

- **Showing the window is what moves the anchor.** `SupportCoordinator.showSupport()` calls
  `markAsked()` on every route into the window — the palette's app menu, Settings → About, the menu
  bar, the launcher command and the reminder itself. Someone who has just read the pitch is not asked
  again next week, however they came to it, and one call site is what keeps that true.
- **The reminder never takes focus from something the user started.** `presentIfDue()` returns without
  presenting unless `AppCore.canInterruptUser`, which is `UpdateReadiness` over `AppCore.currentActivity`
  — the same seven-case gate the update prompt uses, shared rather than copied. A withheld ask leaves
  the anchor alone, so it is still owed and the pump comes back in ten minutes rather than a month.
- **The checkbox defaults on, and off means off forever.** `AppSettings.supportRemindersEnabled` reads
  `defaults.object(forKey:) == nil || defaults.bool(forKey:)`, so absence is on and a stored `false`
  survives. It rides a settings backup: it grants no capability, it silences a prompt, and a user who
  turned it off should stay off across a restore.
- **The schedule state is a file, not a default.** `support-reminder.json` lives under
  `AppPaths.applicationSupport()`, not `caches()` — a purged cache would reset the anchor and ask
  early. It holds `firstSeenAt` and `lastAskedAt` and nothing else; the *preference* stays in
  `AppSettings`, and the two never mix.
- **The first ask lands one interval after first run, not after launch.** With no `lastAskedAt` the
  anchor is `firstSeenAt`, stamped the first time the store finds no file, so a fresh install is
  never asked on day one.
- **One button, one link.** `SupportCoordinator.checkout` is the only destination, and no surface
  restates what is behind it — the checkout page owns that, so nothing here can fall out of step
  with it. Adding a second button means adding a second thing to keep in sync.
- **The button is the composition, not its footer.** It sits under the hero at 46pt tall, because this
  window asks where the update window reports — an actions row pinned to the bottom edge reads as a
  utility dialog.
- **Brand colour appears exactly twice**: the app icon, which is violet on its own, and the button.
- **Support's views are Support's own.** `SupportActionButton` is private to `SupportWindowView`
  rather than reaching for Onboarding's card rows, which are that window's.

## How it is put together

| Piece | Holds |
| --- | --- |
| `Model/SupportReminderSchedule.swift` | pure — seconds until the next ask, clamped at both ends |
| `Service/SupportReminderStore.swift` | the JSON state, and the one `Task` pump that offers the ask |
| `UI/SupportCoordinator.swift` | the window's lifecycle, the checkout link, the anchor write |
| `UI/SupportWindowView.swift` | the window: hero, the button, and the reminder checkbox |

`SupportReminderStore.advance()` is one turn of the pump: it answers how long to sleep, and calls
`onDue` when the wait has reached zero. `AppCore.start()` wires that closure to
`supportCoordinator.presentIfDue()`. The store itself never presents anything and never writes the
anchor on its own — that write belongs to the coordinator, so there is exactly one of it.

The wait after an offer is floored at the retry interval. Showing the window is what moves the anchor,
and the floor is what stops the pump spinning if it did not.

## The window

`AppWindowController` at 460pt wide, taking the height its content measured through
`.onGeometryChange` → `fit(height:)`. It is titled and transparent-titlebar'd, so `ActivationPolicy`
brings the Dock icon in and out on its own, and `⌘W` or the close button dismisses it.

The composition is centred: a shadowed 76pt app icon, the ask in `.title2`, one line of copy, then
the button and the reminder switch. Nothing carries a keyboard shortcut —
with a custom button style there is no focus ring to advertise one, and ↵ silently opening a payment
page is a surprise rather than a convenience.

Only the mechanism is shared with the Software Update window — `AppWindowController`, the
content-measured height and the `sheen` gradient. The layout deliberately is not: that window reports
and closes, so its actions belong in a trailing row; this one asks, so the ask is the centrepiece.

## Where it is reachable from

The palette's bottom-left menu circle (between About and Settings), Settings → About, the menu bar
menu, and the launcher as `CommandID.support`. All four land on `showSupport()`. The launcher arm
hides the palette first, the way `.about` does; the menu-circle row does not, because the panel
dismisses itself on `windowDidResignKey`.
