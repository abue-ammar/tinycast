# App launcher & fuzzy match

`AppIndex.scan()` runs off-main, enumerates the user's search scopes, and dedups by bundle ID (the
earliest scope wins).

## Invariants

- **`AppEntry.Kind` is the only thing that says what an entry is.** One case per launcher section, per
  `VisibilityStore` category and per Settings pane — never re-derive a category by sniffing an entry ID.
  A new category means a new case, a slice in `AppIndex.publishEntries()`, and the matching filter in
  `LauncherList.rows`, in that order.
- **A category's switch is a master switch, not a list filter.** `VisibilityStore.isKindEnabled` gates
  `orderedResults` *and* `HotKeyManager.perform`, so `Enable Applications` off stops the per-app chords
  as well as the rows — the guard sits in the one dispatch funnel, the way each feature switch already
  guards its own. The per-item checkbox beside it is the narrow tool: it hides one row and leaves that
  row's shortcut firing. A new category must be wired into `VisibilityStore.allowsHotKey`, or its
  chords keep running while its pane reads off.
- **`Model/SearchRelevance.swift` is Foundation-only and pure**, so `fuzz-test` compiles the shipped
  scorer. It owns both `FuzzyMatch` and the field bands.
- **Searchable fields stay separate** — display name, Spotlight alternate names, owner name, bundle id
  and executable name are never flattened into one string, because the field is what picks the band. A
  new searchable field means a new `Band` case and a `consider` call, in priority order.
- **`Model/SearchScopes.swift` and `Model/LauncherRankingStore.swift` are pure too** — the ranking store
  takes its clock via `now` and its path via `fileURL`, for `scopes-test` and `ranking-test`.

## Search scopes

`SearchScopes` (`Launcher/Model/SearchScopes.swift`) owns the paths; the list is user-editable in General
Settings and persisted as `AppSettings.searchScopes`. A scope is either a directory or a single `.app`
bundle, stored tilde-abbreviated so the UI reads cleanly and a settings backup stays portable.

Enumeration descends **one subfolder deep** — a scope's own `.app` children, plus any inside an
immediate subfolder, are indexed. That catches vendor-folder installs like
`/Applications/Blackmagic Design/DaVinci Resolve.app` without the folder needing its own scope
(#256). The walk stays bounded rather than fully recursive: it never opens an `.app` bundle's own
`Contents/` tree, because `.app` is treated as a leaf, and a subfolder nested deeper than one level
still needs its own scope.

The defaults cover `/Applications` and `/System/Applications` plus their `Utilities` folders,
`/System/Library/CoreServices/Applications`, the cryptex apps under
`/System/Volumes/Preboot/Cryptexes/App/System/Applications` (this is the only place Safari really
lives — `/Applications/Safari.app` is a symlink flagged hidden, so `.skipsHiddenFiles` never sees it),
`~/Applications`, and `/System/Library/CoreServices/Finder.app`.

Finder ships as an individual bundle scope rather than by adding `/System/Library/CoreServices`, which
holds ~120 background-agent bundles. There is no reliable way to filter those: `LSUIElement`,
`LSBackgroundOnly` and "declares no icon" each also exclude legitimately launchable apps — Raycast,
Stats, Tinycast itself, Mission Control, Siri, Time Machine, Screenshot, System Information, Font
Book. Don't reintroduce such a heuristic.

`AppIndex.start(settings:)` observes `$searchScopes`, so an edit re-indexes immediately; overlapping
refreshes collapse into a single trailing scan.

`FuzzyMatch.score` is a tiered scorer: exact → prefix → substring / word-start → subsequence with
consecutive / word-boundary bonuses. `LauncherRankingStore` then adds a bounded, query-specific
frecency boost (frequency plus decaying recency). The boost can reorder results within a relevance
tier but cannot make a weaker match kind beat a stronger one. Matching strips invisible Unicode
format scalars first, since app metadata can contain bidi/zero-width markers before the visible name.

## Searchable fields

An entry is matched on six fields kept deliberately separate — flattening them into one string would
lose the thing that decides the ranking. `SearchRelevance.score` evaluates each independently and the
strongest one becomes the entry's base relevance:

| Band | Field                                   | Match strength                                    |
| ---- | --------------------------------------- | ------------------------------------------------- |
| 7    | user alias (any entry kind)             | anchored literal — exact / prefix                 |
| 6    | display name (plus a snippet's keyword) | literal — exact / prefix / word-start / substring |
| 5    | Spotlight alternate names, plus a user alias's word-start / substring hits | literal |
| 4    | owner name (the extension a command came from) | literal only                               |
| 3    | display name                            | subsequence                                       |
| 2    | Spotlight alternate names               | subsequence                                       |
| 1    | bundle identifier                       | literal only                                      |
| 0    | executable name (`CFBundleExecutable`)  | literal only                                      |

The arithmetic is what makes that table binding. A band's offset is `rawValue * bandStride`, and:

```
bandStride            = 10 × FuzzyMatch.maximumScore   = 1,000,000
FuzzyMatch.maximumScore                                =   100,000
LauncherRankingStore.maximumBoost                      =     4,500
```

So a field can never reach the band above it — the widest possible fuzzy score is a tenth of a stride —
and the learned frecency boost is two orders of magnitude below a stride, which is what keeps learning
reordering *within* a tier and never across one. Those three numbers are a contract, not a tuning
parameter.

A _literal_ hit on a weaker field outranks a _subsequence_ hit on a stronger one. That is the point of
the split: an alias the vendor actually declared (`Codex` for ChatGPT) must beat the incidental
c-o-d-e…x scattered through an unrelated app's name, while a real prefix hit on a display name still
wins outright.

Identifier fields never subsequence-match — reverse-DNS text is a subsequence of nearly every short
query (`cop` ⊂ `com.apple.Photos`), which would change _which_ apps appear rather than just their
order. For the same reason a bundle id is matched with its leading component stripped
(`apple.Photos`, not `com.apple.Photos`): `com` alone prefixes almost every installed app. The full id
still matches exactly, so a pasted identifier resolves.

### Owner names

An extension's title is a keyword for every command it ships: `lucide` finds Lucide's *Search Icons*
without the user aliasing each command by hand. `AppEntry.ownerName` carries it — the same string the
row already prints as its kind label — and `SearchRelevance` gives it the weakest literal band, for two
reasons. It does not name the entry, so any hit on a command's own title, on another entry's title, or
on a Spotlight alias outranks it; and every command of one extension carries the identical string, so a
subsequence band there would surface a whole extension at once on letter soup. Literal-only keeps that
bounded while a real prefix hit still beats an incidental subsequence elsewhere — the same trade the
identifier fields make, for the same reason.

Because the band is uniform across an extension, its commands score identically and cluster together,
tie-broken alphabetically and then by the learned boost. Ranking a third-party string this low is
deliberate: an extension titled `Safari` can never take that query from the real Safari.

### Category search

A query that *equals* a category's own name lists that whole category under its section header, in the
order the section shows when the field is empty. Both words a kind already carries work — the section
title and the singular label, `Snippets`/`Snippet`, `Window Management`/`Window Command` — read straight
off `KindDescriptor` by `AppEntry.Kind.named(by:)`, so no category name is written a second time and a
new `Kind` case gets its category word for free.

**The trigger is exact equality, never a prefix or a fuzzy hit**, because a looser rule would take a word
away from a real entry: `System Settings` names both a category and an installed application. That one
collision is answered rather than avoided — an entry whose display name equals the query joins the
listing, so the app appears under Applications above the panes. Since slice order is section order
(`publishEntries`), `categoryListing` is a filter with no sort, and the sectioned view stays 1:1 with the
flat selection. Visibility still applies downstream, and no `limit` does, matching the empty query.

`LauncherScreen` therefore separates the two jobs the empty query used to do at once: `showSections`
draws the headers, `pinsFavorites` pins the Favorites prefix and hands out the ⌘-digit slots. A category
listing takes the first only. Opening a row from one also records nothing in `LauncherRankingStore` — a
category word is not a search for the row that ran, and learning it would rank that row under `s`.

### Contextual commands

A **contextual** command is one the query itself supplies the target for, so it exists only while a
query resolves and never sits in the index. `CommandCatalog.contextual` names them, `all` filters
them out, and `LauncherScreen` offers the row per keystroke — ahead of the ranked matches, because
nothing the index holds answers a typed address better. There is one today: typing a web address or
a bare host puts **Open in Browser** on top, and activating it hands the URL to the system's default
handler through `AppLauncher.open`.

The shape a query has to have is `QuicklinkDestination.detect` returning `.web`, reused rather than
re-written so `github.com` and `https://…` mean the same thing here as they do in a quicklink. The
entry is an ordinary `.command`, so `VisibilityStore` still gates it — Commands off hides the row —
and its `url` carries the destination instead of the catalog's `tinycast://` placeholder. Nothing
learns from it and nothing pins it: `LauncherCoordinator.launch` skips `LauncherRankingStore` for a
contextual row, the way it already skips a category listing, since a pasted URL is not a term any
row should rank under; and ⇧⌘F is refused, because a favorite the empty query can never resolve is
dead state a backup would then carry.

The row prints `AppEntry.subtitle` beside its name — the one field for an entry whose name alone
can't say what it acts on.

### Fallbacks

A **fallback** is the other half of the query-driven idea: a command the query is the input for,
offered under a `Use “…” with…` header **below every result**, whatever the query says. A contextual
row leads because it recognised the query; a fallback trails because nothing did.

`Fallback` (`Launcher/Model/`) is the whole vocabulary — `.builtin(Builtin)` for the three shipped
destinations and `.quicklink(UUID)` for a user's own. `Builtin` exists rather than a bare `CommandID`
so `FallbackCoordinator.run` is **exhaustive**: a fourth built-in cannot compile without saying where
its query goes. `Fallback.id` is deliberately the row's own `AppEntry.id`, which is what lets a stored
order name a live row across a rename or a reinstall.

| Fallback | Where the query goes | Offered when |
| --- | --- | --- |
| AI Chat | a fresh chat, question already sent (`AIChatCoordinator.ask`) | `aiEnabled` |
| Search Files | the file-search screen, already narrowed | `fileSearchEnabled` |
| Run Shell Command | `/bin/zsh`, streamed into the Command Output window | always |
| a quicklink | its first `{argument}` | `quicklinksEnabled`, and the link has a placeholder |

**A quicklink earns a fallback row by declaring a placeholder**, nothing else —
`QuicklinkDestination.containsPlaceholder`. `openQuicklink(id:filling:)` assigns the query to the
first *real* missing argument and leaves the rest to the argument form, which opens pre-filled
through `QuicklinkArgumentSession.begin(values:)`. The seed never fills the **selection** prompt:
that one is not an `{argument}` and is resolved by replacing the context, so seeding it through
`userArguments` would silently do nothing.

**Run Shell Command carries its own switch, not the custom-command library's.** Turning off Custom
Commands hides a library of saved commands; it says nothing about a shell line someone types
deliberately. The fallback's checkbox is the switch. The run is an ad-hoc `CustomCommand` that is
never stored — same streaming window, same Stop button — so `CustomCommandCoordinator` keeps
`lastShellCommand` for the window's Rerun, which has no library entry to look up. It sources the
shell config (`ll` should mean the reader's own alias) and takes the runner's default home directory.

**The order and the checkboxes are not in a settings backup.** The fallback list is where an import
could arm shell execution from the launcher, which is the line `snippetsEnabled` already draws:
a flag that grants a capability is never carried by a backup.

`FallbackStore` is a thin persistence shell over `Fallback.ordered(_:by:)`, which is pure and covered
by `fallback-test`: stored ids first, then anything the order has never seen, and a stored id with
nothing behind it — a deleted quicklink — is skipped rather than resurrected. Settings ▸ Fallbacks
lists exactly `FallbackCoordinator.available`, so a fallback whose feature is off is absent from the
pane as well as from the launcher, and reorders through ↑/↓ buttons like a favorite rather than
introducing this codebase's first drag-reorder.

**A fallback row is not a result, and `LauncherScreen.Row` says so.** `.fallback` is its own case
with a `fallback-` prefixed id, because AI Chat can be a ranked hit *and* a fallback in the same
list, and two rows sharing one id would collapse in `ForEach`. That is also why `LauncherList` takes
a `selectedRowID` rather than an entry id. Nothing about a fallback row is learned, pinned or
revealed: `activate` routes to `FallbackCoordinator.run` instead of `LauncherCoordinator.launch`, and
`FallbackActionsMenu` offers only running it and opening the pane.

### User aliases

`AliasStore` (`Launcher/Service/`) keeps one user-chosen alias per entry, keyed by `preferenceKey`
like favorites and learned ranking, so every entry kind — apps, commands, quicklinks, snippets —
can carry one. An alias is deliberate in a way no vendor field is, so a hit **from its start** —
exact or prefix — occupies the top band and ranks its entry first. A hit *inside* the alias ranks
with the Spotlight aliases instead (`term` inside `iterm` must not beat Terminal's own prefix),
and a subsequence of a short alias would be noise, so it never matches at all. `AppIndex` folds the
alias into `SearchFields.userAlias` at rank time, keying its memos on the store's revision.

A launcher row shows its entry's alias as a small chip after the name, so what a badge-bearing
result will answer to is visible without opening anything.

Editing lives in Settings only — an alias is one-time configuration like a shortcut or a
visibility checkbox, not a per-invocation action, so the ⌘K menu stays out of it. Every pane built
on `LauncherItemsSection` puts an `AliasField` on each row, dressed like the `ShortcutRecorder`
beside it; edits store as typed and trim when the field loses focus, and a blank means none. That
list filters by **membership only**, keeping the index's name order — re-ranking it per keystroke
would move the row being edited out from under its own field editor. A pane with a hand-written row
hands `AliasField` the key itself: Settings ▸ Quicklinks passes `Quicklink.entryID`, and dims the
field on a quicklink hidden from root search, whose entry the ranker never sees.

Aliases ride along in a settings backup (`launcherAliases`), and deleting what an alias points at —
uninstalling an app, deleting a quicklink or custom command, uninstalling an extension — removes it
with the entry's other per-entry preferences.

### Alternate names

`SpotlightNames` reads `kMDItemAlternateNames` — the aliases macOS itself knows an app by, which no
Info.plist key exposes: `iBooks` for Books, `iCal` for Calendar, `Address Book` for Contacts,
`System Preferences` for System Settings, `browser` / `浏览器` / `사파리` for Safari. `MDItem.h` exports
no constant for either attribute it reads, so both are named directly.

It also reads `kMDItemDisplayName`, the app's name in the system language, because nothing else
supplies it (#371). Every app under `/System/Applications` keeps its translations in one
`Contents/Resources/InfoPlist.loctable` and none ships an `InfoPlist.strings`, so `CFBundle` resolves
all 65 of them to `en` whatever the system language is — which is why the row label reads English
without being pinned there, and why without this a Portuguese Mac finds Find My as `Find My` and never
as `Buscar`. It measures 12 bundles carrying alternates under `en` against 49 under `pt-BR`. The value
is a file name, so its `.app` comes off first; on an English Mac it then equals the display name and
`usableAlternateNames` drops it, so nothing is indexed twice. Both attributes ride the one `MDItem`
the pass already creates, so the cost below is unchanged.

Leave `Bundle.installedAppName` on `object(forInfoDictionaryKey:)`. Reading `infoDictionary` to force
an English label looks equivalent and is not: FindMy's raw `Info.plist` names it `FindMy`, and
`Find My` lives only in the loctable, so the raw dictionary spells three Apple apps worse — `FindMy`,
`VoiceMemos`, `Siri AI` — and changes nothing else.

Spotlight mixes junk in with the real aliases, and `SearchFields.usableAlternateNames` (pure, covered
by the harness) drops it: every bundle lists its own `<Name>.app` file name, several system apps ship
untranslated `ALTERNATE_NAME_1` placeholders, and some just repeat the display name. Indexing those
would make `app` match the entire index.

A Spotlight round trip costs ~0.8 ms per bundle cold — 76 ms over the default scopes — and the scan
reruns on every launcher open, so `SpotlightNames.Cache` memoizes per bundle path and re-reads only
when the bundle's modification date moves, taking later passes to ~0.2 ms. Each pass is seeded from
the last and keeps only what it looked at, so uninstalled apps fall out instead of accumulating.
`.appex` Settings panes carry no alternate names, so `SettingsPaneScanner` doesn't ask.

Selecting a launcher result records every prefix of the submitted query, so choosing WhatsApp for
`wha` also teaches `w` and `wh`. Direct hotkeys and empty-query favorites do not affect learned
ranking. Learned data stays on device in `launcher-ranking.json`; a result that has learned ranking
offers a per-item reset in its Actions menu, and users can clear all learned ranking in General
Settings.

Rankings are memoized one query deep and keyed by the ranking store's revision, so a launch or reset
invalidates the cached order. `rank` resolves the whole learned table for a query up front via
`boosts(query:)` — one fold and one clock read per pass, not per candidate.

## System actions

`SystemActionCatalog` is a Foundation-only inventory of the macOS actions Tinycast exposes. Its
stable entry IDs, labels, symbols and confirmation policy are covered by
`Tests/system-action-test.swift`; platform side effects live separately in `SystemActionRunner`.
`SystemActionCoordinator.runSystemAction(id:)` remains the one execution funnel — shared by palette activation and a
global hotkey — hiding the floating palette before any confirmation or value dialog and surfacing
permission-aware failures. With the palette closed it targets the frontmost app, so Hide Others and
Quit All act on the same window a palette launch would have.

System actions occupy their own launcher section and their own Settings pane. The empty-query publication
order is applications, System Settings, quicklinks, snippets, system actions, window commands, custom
commands, then built-in commands; the sectioned view filters in that same order so the visible rows remain
identical to the flat selection index.
Search, favorites, visibility and learned ranking work through the normal `AppEntry` path, and every
action is bindable to a global shortcut from Settings › System Actions
(see [hotkeys.md](hotkeys.md)).

Public AppKit, CoreAudio and workspace APIs are preferred. Actions without a stable public macOS API
use fixed system tools, Apple Events, Accessibility, or a dynamically resolved Bluetooth power API.
Those routes run only on explicit activation. Automation, Accessibility or Bluetooth permission is
requested at first use, and denial produces an alert linking to the relevant System Settings pane.
Toggle System Appearance changes macOS; Tinycast follows it only while its own Appearance is System.

Restart, Shut Down, Log Out, Empty Trash and Quit All Applications confirm before execution: ↵ runs
the action, Escape cancels. Every dialog is Tinycast's own: confirmations, failure reports and the Set
Volume slider all render through `DialogController` rather than an `NSAlert`
(see [ui.md](../ui.md#dialogs--hud)). Each confirmation carries the action's own icon — Restart shows
`arrow.clockwise`, Empty Trash `trash.slash` — so the dialog is recognizably about the row that
opened it. Volume and mute actions also show Tinycast's transient volume HUD, since macOS only draws
its own for real media keys. Volume Up/Down walk a 5% grid (`VolumeLevel.stepped`, covered by
`Tests/volume-test.swift`): an off-grid level snaps to the next line rather than past it, so from 37%
up lands on 40% and down on 35%, and repeated presses stay on round numbers.

An action whose effect is invisible reports back through a pill (`MessageHUDController`, the same one
Custom Commands and Snippets confirm through) rather than finishing silently:
`SystemActionRunner.run` returns a `SystemActionFeedback` naming the state it landed in
(`Trash Emptied`, `Hidden Files Shown`, `Dark Appearance`, `Bluetooth Off`, `3 Disks Ejected`), and
`AppCore` shows it with a `DialogTone` derived from the feedback's `isNoOp` flag: `.success` when
something actually changed, `.neutral` when there was nothing to do, shown as the glyph trailing the
message rather than a per-action icon, since the message already names the state. Actions that are
their own confirmation, such as Show Desktop, Hide Others,
Quit All and the power actions, return nothing. Volume and mute are the one case that stays on the
palette's own box HUD, since that one has an actual level and number to show, not just a message.

**Nothing-to-do is an outcome, not a failure.** Empty Trash asks Finder for `count items of trash`
first and reports `Trash Is Already Empty`, because Finder raises an error when told to empty an empty
Trash. The count deliberately goes through Finder instead of reading `~/.Trash` directly: that folder
is TCC-protected, so an unprivileged read fails in a way indistinguishable from "empty", which would
silently skip a real empty. Eject All Disks, Dismiss Notifications and Unhide All Apps report the same
way when there is nothing to act on. Volume and mute fall back to the output's preferred stereo channels when the device exposes
no master element (common on HDMI), and Toggle Mute parks the level at zero when there is no mute
control at all. Multi-disk ejection takes every external or ejectable volume — a dock's fixed-media
HDD reports as neither ejectable nor removable, so external alone qualifies — while excluding
internal, network and root volumes, treats a sibling volume that the same physical eject already
unmounted as done, counts a volume whose eject errored but whose mount is gone as ejected, and
reports remaining failures together.
Preference-backed toggles refuse to write when the current value can't be read, and notification
dismissal matches Accessibility subroles rather than English labels.

## Window commands

`WindowCommandCatalog` supplies the 32 window actions as a static slice, published as a whole by
`AppIndex.setWindowCommandsVisible(_:)` and shown under a "Window Management" section. Like system
actions they carry dedicated global hotkeys (`AppEntry.hotKeyAction` returns `.windowCommand(id:)`),
so launcher rows render keycaps for them. Their per-command shortcut and visibility controls live in
Settings › Window Management rather than a launcher-category pane of their own — the same call already
made for snippets. The feature ships off. See
[window-management.md](window-management.md).

## Quicklinks

`QuicklinkStore` supplies its slice the same way custom commands do, sorted pinned-first then
alphabetically by `Quicklink.precedes`. Only the name is indexed — a URL is a subsequence of nearly
any query — and a per-item "show in root search" flag filters the slice before it is published. The
four Quicklinks commands are dropped from the built-in slice in the same publish while the feature is
off, so a toggle can't leave the section and its commands out of step. See
[quicklinks.md](quicklinks.md).

## Custom commands

`CustomCommandStore` supplies user-authored entries to `AppIndex` without joining the off-main
application scan. Custom commands are their own alphabetized section ahead of the built-in Commands
section, and reuse fuzzy ranking, favorites, visibility, keycap rendering and the launcher's flat
selection.

Only the display name is indexed. Activation resolves the stable UUID through the store and dispatches
to `ShellCommandRunner`; see [custom-commands.md](custom-commands.md) for persistence, hotkeys and
execution semantics.

## Quick Action commands

`CommandID.fixGrammar`, `.rewrite`, `.translate` and `.summarize` publish the four Quick Actions
while `quickActionsEnabled` is on, each carrying the action's own title and glyph so the launcher row
and the settings row can never drift. `CommandID.init(_ action: QuickAction)` is exhaustive, so a
fifth action cannot reach the launcher without one.

Activation hands the action to `QuickActionCoordinator.run(_:)` **without** hiding the palette first:
the coordinator reads the displaced app and then hides, because after the hide the frontmost app is
Tinycast. See [quick-actions.md](quick-actions.md).

## Notes commands

`CommandID.showNotes`, `.createNote`, and `.searchNotes` publish the three Notes entry points while the
feature is enabled. Activation hides the palette without restoring focus and calls the matching
`NotesCoordinator` action; each `HotKeyAction` reaches that same boundary and rechecks enablement.

`AppIndex` projects the three commands together from `notesEnabled`, independently of File Search and
Quicklinks. They represent collection actions rather than individual notes, so Notes adds no
`AppEntry.Kind` or launcher section. See [notes.md](notes.md).

> **Invariant:** `Tests/fuzz-test.swift` compiles the real `Tinycast/Features/Launcher/Model/SearchRelevance.swift`, so
> that file must stay Foundation-only and pure. There is no copy of the scorer to keep in sync.

The ranking harness covers prefix learning, frequency/recency scoring, persistence, and both reset
paths; see the command in `development.md`.

Launcher icons use a persistent 32 MB cost-capped `NSCache`. Fitted file-row icons use a separate
transient 8 MB cache that is purged when its palette list disappears (`IconCache`).

A file-icon key carries a `FileIconStamp` as well as the path — the bundle's own modification and
attribute dates plus its `Icon\r` — because pasting a custom icon in Finder leaves the bundle's
contents alone, so a path-only key served the bitmap decoded first for the rest of the session.
`AppIndex.scan` reads the stamp off-main into `AppEntry.iconStamp`, `EntryIcon.file` carries it, and
because it is part of `iconKey` the re-scan on the next palette open re-decodes exactly the apps
whose icon moved.

## Favorites

`FavoritesStore.keys` is the order — the array *is* the ranking, and it only shows while the query is
empty, where `AppIndex.orderedResults` pins it as a prefix of the results. `LauncherScreen` resolves
that prefix once in `init` (`favoriteCount`), and the list, the reorder rows and the chord guards all
read that one number, so the visible section and what a move acts on can't disagree.

The ⌘K menu carries **Add / Remove from Favorites** (⇧⌘F) plus **Move Favorite Up / Down** (⌥⌘↑ /
⌥⌘↓). A move row is only built in a direction that exists, so the first favorite has no Up row and
the last has no Down.

**Every one of those rows runs the same call its chord does** — the menu is handed an
`AppActionsMenu.FavoriteActions` built by `LauncherScreen` and never touches `FavoritesStore` itself.
A row that mutates the store directly looks identical on screen and then behaves differently from its
chord, because the store knows nothing about where the highlight should land.

`FavoritesStore.exchange` swaps two stored positions rather than removing and re-inserting. `keys`
retains entries that `VisibilityStore` hides or that aren't currently indexed — `ordered(_:)` drops
them with `compactMap` and never prunes them, which is how a favorite survives an unmounted volume —
so exchanging the two *visible* keys leaves every such key on its own slot.

Both actions re-ask `orderedResults` afterwards and restate `vm.selection` against it; the mutation
already invalidated the memo, so that call warms the exact key the next render reads. Where the
highlight lands differs on purpose: a **move** follows the entry, since the point of the action is
where that entry now sits, while a **toggle** stays with the section rather than chasing an entry
across the list — the top of Favorites on add, the neighbour above the one that left on remove.

### ⌘-digit slots

`FavoriteSlots` (`Launcher/Model/FavoriteSlots.swift`) defines ten local palette slots: **⌘1…⌘9 then
⌘0**. They match the physical number row, not the character produced by the current keyboard layout,
so the same positions work on QWERTY and AZERTY. The same slots address pinned Clipboard entries in
that screen; the eleventh favorite is still listed and reorderable, and simply has no slot.

Both palette sizes serve the chords from the same prefix, because `paletteIsCollapsed` already
requires an empty query: **compact implies empty implies `favoriteCount` is the pinned prefix**. That
is why `LauncherScreen.pinnedFavorites` feeds the strip, the chords and the numbered rows alike,
rather than the compact bar re-deriving an empty-query order of its own. In compact the strip draws
the first five; ⌘6–⌘0 still launch favorites it has no room for, and the "…" is a button after them
rather than a slot, so no favorite loses its digit to the overflow.

Holding ⌘ swaps each numbered row's kind label for its chord. `PalettePanel` publishes the modifier
into `PaletteState.commandHeld` from `.flagsChanged` and clears it in `resignKey` — not in `prepare`,
which a re-show that preserves state skips entirely. **`AppRow` observes that flag itself**: reading
it any higher would attach it to `RootPaletteView`'s body and rebuild the whole palette on every ⌘
press, where a row-level read re-runs only the handful of rows the `LazyVStack` has realized. The
digit each row shows is carried on its `Row` case from the section build, so no row searches for its
own position.

## Reveal in Finder

Application and System Settings results expose **Show in Finder** in their ⌘K Actions menu and on
**⌘↵**. Synthetic command results have no filesystem location, so neither the menu row nor the
shortcut is available for them. `AppEntry.canRevealInFinder` is the one rule both the menu row and
the key handler read, so the advertised chord can't drift from the behavior.

## Quitting and restarting apps

`RunningAppsMonitor` (live from `NSWorkspace` launch/terminate notifications) drives both the row's
running dot and the availability of the running-only actions:

- **Quit Application** — a row of an app's ⌘K Actions menu, shown only while that app is
  running, also bound to **⌃⇧Q** on the selected row. The chord guard mirrors the menu row's
  condition (an `.application` entry that `RunningAppsMonitor` reports running) so the key never
  swallows a press it won't act on, and it's skipped in the compact bar, which shows no selection.
  `AppLauncher.quit(bundleID:)` terminates every instance of the bundle and reports whether
  anything was running; the palette only dismisses when something was, and it restores focus unless
  the app it just quit _was_ `previousApp`.
- **Restart Application** — the row above it and **⌘R**, on the same guard: both chords resolve
  their target through `LauncherScreen.runningApplication(at:)`, the single place that condition
  lives. `AppLauncher.restart(bundleID:url:)` snapshots the running instances, subscribes to
  `NSWorkspace.DidTerminateApplicationMessage` _before_ terminating so an instance that exits at
  once can't outrun the wait, then reopens the bundle once every snapshotted PID has gone. The wait
  is bounded by a five-second grace: a quit an app refuses, or one sitting behind a save sheet the
  user leaves standing, relaunches nothing and leaves that app running. The palette dismisses the
  moment the quit is asked for and never restores focus — either the relaunch takes it, or the app
  that refused the quit is the one asking for it.
- **Quit All Applications** a system action. `AppLauncher.quitAllTargets()` is the
  policy (every `.regular` app except Finder — `terminate()` only relaunches it — and Tinycast,
  excluded by PID because About/Settings temporarily flips it to `.regular`). `SystemActionCoordinator.quitAllApps()`
  resolves that list **once**, confirms it with an `NSAlert`, then terminates exactly what was
  confirmed. The palette hides before the alert — it is a floating panel and would sit above it.

Both quits are graceful `NSRunningApplication.terminate()`, so an app with unsaved work still puts up
its own save sheet.

The ⌘K menu samples `isRunning` **once, when it opens** (`RootPaletteView.openActions()`), so an app
launching or quitting elsewhere can't add or drop those two rows while the menu is up — the same freeze
the rest of the menu already has ([palette.md](palette.md)). Only `LauncherList` observes
`RunningAppsMonitor` live, for the running dot.
