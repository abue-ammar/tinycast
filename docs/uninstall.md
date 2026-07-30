# Uninstalling apps

An application result's ⌘K Actions menu ends with **Uninstall Application…** (also **⌃⌫** on the
selected row). It opens the palette's uninstall screen: the app bundle plus every support file found
for it, each row a checkbox, everything checked.

The screen has three phases (`UninstallPhase`), and the palette stays open across all of them — a
destructive action that ends by silently closing the window leaves the user nothing to check:

1. **Selecting** — the filterable, sortable list of checkboxes.
2. **Removing** — a progress line naming the app and which removal is running.
3. **Done** — a summary: how many items went, how much was reclaimed, whether it's recoverable from the
   Trash, and any paths that couldn't be removed (with the two reasons: needs an administrator, or still
   in use). `↵` / the footer's **Back to Search** ends the session and returns to a fresh root search —
   it never closes the palette. Finishing an uninstall isn't the same as being done with Tinycast, so
   closing stays the user's call (`⎋` from the launcher, as everywhere else).

Two removal paths, pairing the way Finder's do:

- **Move to Trash** (`↵`, the footer default) — recoverable, so it needs no second confirmation: the
  list *is* the confirmation.
- **Permanently Delete…** (`⇧⌘⌫`, Finder's own chord) — unlinks outright, and is the one action in the
  flow that puts up a confirmation alert first, since nothing can walk it back. ↵ in that alert goes to
  **Cancel**, so a reflexive second Return can't erase anything; cancelling returns to the same screen
  with the checkboxes intact.

## The screen

`PaletteMode.uninstall` is a sub-screen like Clipboard and Emoji, so it reuses the palette's flat
selection, footer and ⌘K menu. The header field **filters** the list (`UninstallSession.filtered`, a
case-insensitive substring over file name and path), and a sort control beside it orders the rows by
path, size or name. The footer is the standard one — app-menu circle on the left, primary action plus
Actions on the right — because a screen that swaps out shared chrome reads as a different app.

The checked count and total render through the shared **`SectionHeader`**, as this list's first row inside
the scroll view. Not a fixed strip above it: the header component *is* the alignment, so the line sits
exactly where "Favorites" or "Applications" sits in every other list and nothing shifts between screens.

`filtered(_:)` — not `items` — is what the selection, the ⌘K menu and every activation address. Any new
code path that resolves "the highlighted row" has to go through the same filtered list, or it will act on
a different row the moment a filter is typed.

Because the field types, **a literal space can't be entered there**: bare space is intercepted as the row
toggle before the field editor sees it (`PalettePanel.onBareSpace`). Substring matching makes that a
non-issue in practice.

| Key | Action |
| --- | --- |
| `␣` | Check / uncheck the highlighted row (a click does the same) |
| `↵` | Move every checked path to the Trash |
| `⇧⌘⌫` | Permanently delete them instead (confirms first) |
| `⌘↵` | Show the highlighted path in Finder |
| `⎋` / `⌫` | Back out to the root search — abandons a list, dismisses a summary; ignored while a removal is in flight |

Backing out puts the launcher back **exactly as it was**: `beginUninstall` records the list's live scroll
offset (`PaletteViewModel.launcherScrollOffset`, mirrored from `LauncherList` and deliberately not
`@Published` — it changes on every scroll tick), and both exits set `pendingSelectionID` so the row is
re-selected.

Restoring by *row* isn't equivalent: `ScrollViewProxy` can only scroll to a row, and its minimal scroll
lands that row against a viewport edge rather than where the user was looking. `LauncherList` therefore
takes a `restoreOffset` and applies it through `ScrollPosition` **when it mounts**, reporting back so the
value is dropped and never re-applied — the list owns that timing, so no caller has to wait a turn for it,
and the shared `ScrollIntent` stays free of a case only one list could use. After a successful uninstall
the row is gone, so only the position is restored, one row shorter.

The screen **survives a dismissal**. Clicking away or switching apps hides the palette as usual, but
`schedulePopToRoot` exempts a live session (the scan and the checkboxes are real work), and
`showPalette` restores the screen on the next generic summon — the palette hotkey, "Open Tinycast" in
the menu bar, or a Dock reopen. Asking for another screen *by name* (the clipboard or emoji hotkey, a
palette command) ends the session instead, since that is an explicit request for something else. `⎋`,
`⌫` and the back chevron are the deliberate exits, and a completed removal clears it. That also makes
**Show in Finder** usable mid-flow: inspect a path, summon again, carry on with the same list.

Space and bare backspace are intercepted in `PalettePanel.sendEvent` (`onBareSpace`, `onBareBackspace`)
— the field editor consumes both before SwiftUI's `onKeyPress` could see them.
Row order is exactly what the sort control produced, so the flat selection index maps 1:1 onto the visible
rows; the count header is a non-selectable display row, like every other `SectionHeader`.

## Discovery

`AppLeftovers` (`Core/AppLeftovers.swift`) is Foundation-only and pure — home directory and the
sibling-install flag are injected — so `Tools/leftovers-test.swift` compiles it standalone and drives
it against a throwaway home. The policy is deliberately narrow, and the guards are the point:

- Only the `~/Library` subtrees in `allowedRoots` are searched (Application Support, Caches, Logs,
  Preferences (+ ByHost), Saved Application State, Containers, Group Containers, Application Scripts,
  WebKit, HTTPStorages, Cookies, SyncedPreferences, Autosave Information, LaunchAgents).
- Matches are keyed on the **bundle id** (exact, plus dotted-boundary prefixes for helper/extension
  ids such as `com.acme.app.helper`, and the team-id prefix on group containers) or on the **app
  name** and its no-space / hyphen / underscore variants.
- Every result is re-checked by `isSafeResult`: it must be a *proper* descendant of an allowed root,
  never a root itself, never home, never reachable via `..`.
- A bundle id that isn't plain reverse-DNS is refused outright rather than sanitized, and a name
  shorter than three characters matches nothing — a short folder name is likelier another app's data.
- When another registered install shares the bundle id (`Xcode.app` beside `Xcode-beta.app`), *every*
  keyed path is ambiguous, so `siblingBundleExists` drops all of them and only the bundle is offered.
- `canUninstall` refuses anything under `/System` or `/usr`, any `com.apple.*` bundle id (by id as well
  as by path, so the cryptex-delivered apps and a relocated copy are both covered) and every Tinycast
  channel. **The action isn't offered for those at all** — no ⌘K row, no ⌃⌫. Raycast does show a system
  app's files as locked rows, but a screen on which nothing can be removed only invites the user to try.

Sizes come from `AppLeftovers.size`, an allocated-size tree walk, and the scan is **two-stage** for that
reason. Discovery is a handful of `stat`s and lands at once; sizes are measured afterwards, one path at a
time, and each row fills in as its measurement returns. A size is a full tree walk — cold, a 3.5 GB bundle
measured 32s on the author's machine against 116ms warm — so making the list wait on it would read as a
hang. Rows are therefore usable (checkable, sortable, removable) before any size exists, which is also
why `UninstallRow` renders no size column until one lands.

A **symlink is never sized through**: `size` returns nil for one. A cask's `/Applications` alias points at
the bundle that already has its own row, so following it would count the same gigabytes twice.

### Locked rows

Eligibility decides whether the screen opens at all; removability then decides, row by row, what may
actually go. Both matter, because an app Tinycast will happily uninstall can still own a file it can't
touch:

- `AppLeftovers.isRemovable` asks the filesystem: the parent must permit deletion (which is what protects
  `/System` and anything root owns) and the path must carry no immutable or SIP-restricted flag.
- `AppLeftovers.isProtectedVendor` is what keeps Apple's apps out of the flow entirely (read by
  `canUninstall`), so locks are left to handle the third-party cases: a root-owned bundle, an immutable
  file, a path whose parent the user can't write.
- A locked row renders with a padlock instead of its file icon, dimmed, with an outline-only checkbox. It
  never enters `checked` (`begin` seeds only removable rows) and `toggle` refuses it, so the checkbox
  can't be forced. The header counts checked rows against **removable** rows, not against every row.

This replaces the old design, which checked everything and reported the failures afterwards — telling the
user up front what can't go is cheaper than letting them submit and reading an error.

Support-file **deletion is user-level only**. System paths (`/Library/LaunchDaemons`, privileged
helpers, system extensions) are never discovered and never removed — removing those needs an
administrator, and leaving them behind is the fail-safe direction.

## Removal

`UninstallSession.remove(_:permanently:)` takes the set the caller approved (so what a confirmation
counted is what gets removed) and quits the app first **only when its bundle is among those items** —
unchecking the bundle to clear caches alone never force-quits an app you're still using. The quit is a
graceful `terminate()` plus a bounded 3s wait: removing a bundle out from under a running process leaves
a zombie, and the removal can fail outright while the app holds its own files open. It then hands the list to `AppLeftovers.remove(_:permanently:)` off-main
(`trashItem`, or `removeItem` on the permanent path) and returns whatever failed. That loop lives in
the Foundation-only core rather than here so the harness can drive it; one item failing never stops the
rest, since a root-owned bundle shouldn't leave the support files it came with behind.

A bundle that is only a symlink into `/Applications` (a Homebrew cask points at its Caskroom payload)
is resolved, so the real bundle goes to the Trash and the dangling link goes with it.

`AppCore.confirmUninstall(permanently:)` leaves the palette up (the phase change is the feedback), then
drops the app's own Tinycast state — favorite, hidden flag, learned ranking, bound hotkey — and
re-indexes. Failures are reported on the summary screen, not in an alert, and are never retried with
more force. The one modal in the flow is the permanent-delete confirmation, and only for that does the
palette step aside — it is a float panel and would otherwise sit above the alert — returning either way.

`AppCore.exitUninstall()` is the single phase-aware exit shared by `⎋`, the back chevron and the bare-`⌫`
hook: abandoning a list is free, a removal in flight can't be called back (so it does nothing — hiding
would drop the one screen that reports the result), and a finished one returns to the root search via
`finishUninstall()`. Neither path closes the palette.
