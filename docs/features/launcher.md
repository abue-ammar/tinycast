# App launcher & root search

`AppIndex.scan()` runs off-main, enumerates the user's search scopes, and dedups by bundle ID (the
earliest scope wins).

## Invariants

- **`AppEntry.Kind` is the only thing that says what an entry is.** One case per launcher section, per
  `VisibilityStore` category and per Settings pane — never re-derive a category by sniffing an entry ID.
  A new category means a new case, a slice in `AppIndex.publishEntries()`, and the matching filter in
  `LauncherList.rows`, in that order.
- **A category's switch is a master switch, not a list filter.** `VisibilityStore.isKindEnabled` gates
  `orderedResults` *and* `HotKeyManager.perform`, so `Enable Applications` off stops the per-app chords
  as well as the rows. Its Settings switch stays available while the application
  list disables beneath it — the guard sits in the one dispatch funnel, the way each feature switch
  already guards its own. The per-item checkbox beside it is the narrow tool: it hides one row and
  leaves that row's shortcut firing, and **Hide from Search** in the ⌘K menu ticks that checkbox off for the
  kinds whose pane can tick it back on. A new category must be wired into
  `VisibilityStore.allowsHotKey`, or its chords keep running while its pane reads off.
- **One command, one pane, one switch.** `SettingsTab.ownedCommands` is the whole table of which pane
  lists a command's shortcut, alias and launcher checkbox. A feature that names its commands there
  already decides whether they exist, so `Enable Commands` neither lists nor gates them — two switches
  over one row is how somebody ends up with Notes on and its shortcut dead. Everything the table does
  not name belongs to Settings › Commands and answers to that switch.
- **The ranking lives in pure files.** `Model/LauncherMatch.swift` (the scorer),
  `Model/LauncherOrder.swift` (the comparator) and `Model/LauncherSuggestions.swift` are
  Foundation-only and pure, so `fuzz-test` compiles the shipped code. Changing a rule means changing
  [Ranking](#ranking), never adding a tuning constant.
- **`Model/EntryNaming.swift` is the only place a name is decided, for every kind alike.** A producer
  fills `EntryNaming.Sources` — title, alternate titles, subtitle, keywords — and `profile(for:)`
  lowers it to the `SearchProfile` the comparator reads. A new naming criterion picks one of those four
  fields; needing a fifth means the criterion was modelled wrong.
- **`EntryNaming.profile` runs over every kind, once per index change**, so a naming rule can never
  apply to applications and quietly skip snippets — and nothing is built per keystroke. `AppIndex.scan`
  names the app slice on its own, off-main: transliterating a CJK index is ICU work, and
  `publishEntries` runs on the main actor whenever any unrelated slice changes.
- **The fields stay separate.** Which field matched is half of what the comparator reads — an exact
  subtitle, an exact alternate title and a keyword hit are three different rules.
- **`Model/SearchScopes.swift` and `Model/LauncherRankingStore.swift` are pure too** — the ranking store
  takes its clock via `now` and its path via `fileURL`, for `scopes-test` and `ranking-test`.

## Search scopes

`SearchScopes` (`Launcher/Model/SearchScopes.swift`) owns the paths; the list is user-editable in
Settings → Applications → Search Scopes and persisted as `AppSettings.searchScopes`.
A scope is either a directory or a single `.app`
bundle, stored tilde-abbreviated so the UI reads cleanly and a settings backup stays portable.

Enumeration descends **one subfolder deep** — a scope's own `.app` children, plus any inside an
immediate subfolder, are indexed. That catches vendor-folder installs like
`/Applications/Blackmagic Design/DaVinci Resolve.app` without the folder needing its own scope
(#256). The walk stays bounded rather than fully recursive: an `.app` bundle is a leaf except for
its `Contents/Applications` and `Contents/Developer/Applications` folders, where Xcode ships
Instruments, Icon Composer and Simulator, and a subfolder nested deeper than one level still needs
its own scope.

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

## Search fields

| Field | What lands in it | Compared against | Ranks |
| --- | --- | --- | --- |
| title | the display name | the query read into Latin | yes |
| alternate titles | the bundle's names in the user's other languages and English, a renamed bundle's file name, `CFBundleAlternateNames`, a snippet's keyword | the query as typed | yes |
| subtitle | an extension's title, or a row's own subtitle in its place | the query read into Latin | yes |
| keywords | the declared Info.plist name, an extension command's `keywords`, a meeting's calendar, and the title and subtitle joined both ways | the query read into Latin | no — they only make an entry appear |

An entry appears when the user's alias is an exact or prefix hit, or when any field passes the
sensitivity — an alias that is neither counts as one more alternate title. Bundle identifiers and
executable names are not matched.

## Ranking

`fuzz-test` pins the scorer's values and every rule of the comparator.

### The scorer

`LauncherMatch.match` finds the best alignment of the query over one field's text:

| Matched character | Points |
| --- | ---: |
| the query's first, on the text's first | 4 |
| on a word start — just after a separator | 3 |
| anywhere else, a separator on the same separator included | 2 |
| a separator on a different one, like a space on `-` | 1 |
| not adjacent to the previous match | −1 |

Separators are space, tab, newline and `- . / ( ) [ ]`. In an ASCII name a word also starts at a capital
after a lowercase letter (`OrbStack`), at a letter after a digit (`1Password`), and at the last capital
of a run that a lowercase letter follows (`BBEdit`), so `stack` finds OrbStack while `code` stays
mid-word in Xcode. A query separator with nothing to land on is skipped. An equal text is `exact`, above
every score. The alignment keeps a running maximum, so a row costs O(text).

### Sensitivity

**Search sensitivity** in Settings › General › Search decides how loose a hit may be. *L* is the query
length less its skipped separators:

| Setting | A hit shows when |
| --- | --- |
| Low | it aligns at all |
| Medium, the default | `score ≥ 1.5·(L−2)+4` |
| High | `score > 2·L` |

Medium is the default: a run inside a word (`code` for Xcode, `pec` for Accessibility Inspector) shows,
and so does a gapped hit that starts on a word (`pec` for Previous Track), each ranked below the
stronger hits. High keeps both out while initials (`vsc`) and later words (`chrome`) still land; Low
shows anything that aligns.

### The comparator

The first rule that separates two entries decides:

1. An exact alias.
2. A boosted term — `ai` and `chat` for AI Chat — unless the other entry is used more.
3. Past three characters, an exact title or alternate title.
4. An exact past search term.
5. An exact subtitle, so typing an extension's title lists its commands.
6. An alias prefix.
7. A past search term that starts with the query.
8. A past search term of three or more characters that the query runs at most three past.
9. The best score over the title, alternate titles and subtitle.
10. Frecency.
11. The title's own score.
12. A title or alternate title that starts with the query, so `ap` puts App Store above AirPort
    Utility, which reaches the same score by skipping to `Port`.
13. Kind priority.
14. The name, compared numerically.

Two entries that both meet rule 3 go by search-term strength, then frecency; both meeting rule 4 go by
frecency; both meeting rule 5 go by frecency, then the title's own score. The tiebreak settles the rest —
what the empty list sorts by too — and is frecency, then having an alias, then kind priority, then the
name. Rule 5 applies at any length, which is why `zed` lists the Zed extension's commands above
the Zed app: rule 3 only protects an exact title past three characters.

### Kind priority and boosts

- **Apps win the ties.** `KindDescriptor.rankPriority` puts applications (4) above command-like kinds
  (3), quicklinks (2), and System Settings panes and meetings (1), so a first-party app is never
  shadowed by the Tinycast command named after it: Calculator over Calculator History.
- **One boosted command.** Only AI Chat carries boosted terms (`CommandID.boostedTerms`); boosting Show
  Notes would shadow Apple's Notes.
- **Two entries with the same alias** fall through to the next rule.

`settings` is the case these were measured against. Apple declares `Settings` in System Settings'
`CFBundleAlternateNames`, so it is an exact alternate title and wins rule 3; the command is named
`Tinycast Settings`, like About, Quit and Support Tinycast, so nothing ties it there.

## One fold, everywhere

`FuzzyMatch.normalized` is the only text fold in the launcher: NFC precomposition, format scalars
stripped, then `[.caseInsensitive, .diacriticInsensitive, .widthInsensitive]` with `locale: nil`.
`SearchText` applies it once per field and once per query, learned search terms are stored in it, and
alternate-name dedup, category lookup and rename dedup all call it. A full-width IME query therefore
matches, and is learned, under the same key. ASCII text skips ICU entirely on a fast scalar check.

## Names in the user's language

`BundleLocalization` reads both `InfoPlist.loctable` and `<code>.lproj/InfoPlist.strings` for
`Locale.preferredLanguages` plus English. This matters because `CFBundle` resolves only
`InfoPlist.strings`, and every app under `/System/Applications` translates in the loctable alone — so
all 65 of them read English on every Mac, whatever language it is set to.

A tag carrying a script is read under two more codes, because no one folder name covers it: a
`zh-Hans-CN` Mac also reads `zh-Hans`, the folder most third-party apps ship, then `zh_CN`, the key
Apple's own loctables use. A script-only `zh-Hans` maximizes to reach the same region. A tag without a
script, every English one included, produces exactly the codes it always did.

The user's own language wins the **display name**, so a row reads the way Finder reads it. The rest,
English included, ride along as alternate titles, matched as typed and never transliterated.

**A bundle ships no table for the language it is already written in, so `CFBundleDevelopmentRegion`
places its untranslated name — an app's file name, a pane's `Info.plist` — in the walk at that
language's own position.** Apple omits a loctable's `en` key exactly when the base name already says
it in English: `Tips.app`, `Calculator.app` and `AppleIDSettings.appex` all do, and without this the
walk fell straight past English into whatever *second* language the Mac listed, so an English Mac
with Russian under it labelled them `Советы` and `Аккаунт Apple`. A real table for that same language
replaces the base name outright — `VoiceMemos.app` does ship `en`, so `Voice Memos` is its English
name, and a pane's `TrackpadExtension` is never indexed for `text` to find. The app scan still adds
every file name as an alternate title. Reading the `en_GB` those bundles *do* carry is the wrong
repair: it relabels `Print Center` as `Print Centre`. Below the development region the walk carries on,
so every language under it stays indexed as an alternate title. The region is canonicalized before it is
matched, because `CFBundleDevelopmentRegion` still ships its pre-BCP-47 spelling — Safari's and
Terminal's read `English`. `AppDisplayName.inInfo` reads the `-macos` variant of each key before the
bare one, the way `CFBundle` does: Image Playground's loctable spells the bare `CFBundleDisplayName`
`Playground` and only the suffixed key `Image Playground`. A non-English user finds their app by the
name they see *and* by the English name the vendor advertises.

### Non-Latin names

A title, subtitle or keyword in another script is matched through its Latin reading, and the query is
read the same way, so a name typed in its own script is still an exact hit. `ScriptRomanization.latin`
routes per script and keeps one space between words, which is what lets both `wx` and `weixin` reach
`微信` (`wei xin`) through word starts: no initials are minted.

| Script | Rule | Example |
| --- | --- | --- |
| Han | ICU `.mandarinToLatin` | `微信` → `wei xin` |
| Japanese | the kana only — ICU would read the kanji as Mandarin | `メモ帳` → `memo` |
| Cyrillic | an explicit BGN table — ICU is scientific, and users are not | `Телеграм` → `telegram` |
| everything else | ICU `.toLatin` | `Ελληνικά` → `ellenika` |

It fires only when transliteration actually changes the letters: `Adobe — Creative Cloud` and
`Café Noir` are Latin already. **Kanji readings are not solved, only routed** — a Japanese app whose
name is pure kanji gets a Mandarin reading, which is why the English localization is indexed too.

**Only what an entry is called in the user's languages is indexed.** Spotlight's
`kMDItemAlternateNames` merges every language a bundle ships — Safari's lists `浏览器` and `사파리` — so
romanizing them would let `ll` and `sap` find Safari on an English Mac. Nothing reads Spotlight:
localized names come from `BundleLocalization`, which walks the same loctables Spotlight indexes
(every `kMDItemDisplayName` in the default scopes is among its names), and an app's other names come
from its own Info.plist.

A renamed bundle is the other half. A Finder rename never touches `CFBundleDisplayName`, so the
on-disk basename is indexed as an alternate title — rename `Slack.app` to `Work Chat.app` and both find
it. Duplicate copies dedupe by bundle id, and the losing copy lends its file name to the winner
rather than being dropped whole.

### Subtitles

An extension's title is the subtitle of every command it ships; a command's own manifest subtitle takes
its place, and the title then rides as a keyword. A subtitle ranks like a title in rule 9, and an exact
one is rule 5: `brew` lists Brew's commands above any title that merely starts with it, by usage, then
by the title's own score, then by name. The subtitle does not name the entry, so a title scoring the same wins rule 11.

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
(`publishEntries`), `categoryListing` filters and then sorts within each kind's run, as the empty list
does, and the sectioned view stays 1:1 with the flat selection. Visibility still applies downstream,
and no `limit` does, matching the empty query.

`LauncherScreen` therefore separates the two jobs the empty query used to do at once: `showSections`
draws the headers, `pinsFavorites` pins the Favorites prefix and hands out the ⌘-digit slots. A category
listing takes the first only. Opening a row from one records the visit but not the word — a category
word is not a search for the row that ran, and learning it would rank that row under `s`.

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
learns from it and nothing pins it: `LauncherCoordinator.launch` records no visit for a contextual
row, since a pasted URL is not a term any row should rank under; and ⇧⌘F and ⇧⌘H are both refused,
because a favorite — or a hidden-item key — the empty query can never resolve is dead state a backup
would then carry.

The row prints `AppEntry.subtitle` beside its name — the one field for an entry whose name alone
can't say what it acts on.

### Fallbacks

A **fallback** is the other half of the query-driven idea: a command the query is the input for,
offered under a `Use “…” with…` header **below every result**, whatever the query says. A contextual
row leads because it recognised the query; a fallback trails because nothing did.

`Fallback` (`Launcher/Model/`) is the whole vocabulary — `.builtin(Builtin)` for the four shipped
destinations and `.quicklink(UUID)` for a user's own. `Builtin` exists rather than a bare `CommandID`
so `FallbackCoordinator.run` is **exhaustive**: a fifth built-in cannot compile without saying where
its query goes. `Fallback.id` is deliberately the row's own `AppEntry.id`, which is what lets a stored
order name a live row across a rename or a reinstall.

| Fallback | Where the query goes | Offered when |
| --- | --- | --- |
| Quick AI | a fresh Quick AI chat, question already sent (`QuickAICoordinator.ask`) | `aiEnabled` |
| Search Files | the file-search screen, already narrowed | `fileSearchEnabled` |
| Run Shell Command | `/bin/zsh`, streamed into the Command Output window | always |
| Define Word | the dictionary screen, already showing the entry (see [dictionary.md](dictionary.md)) | the Define Word command is visible in Settings › Commands |
| a quicklink | its first `{argument}` | `quicklinksEnabled`, and the link has a placeholder |

**A quicklink earns a fallback row by declaring a placeholder**, nothing else —
`QuicklinkDestination.containsPlaceholder`. `openQuicklink(id:filling:)` assigns the query to the
first declared argument and opens at once when that was the only one owed; anything still missing
sends the row to Search Quicklinks with its header fields pre-filled (see
[quicklinks.md](quicklinks.md#arguments)). The seed never fills the **selection** field: that one is
not an `{argument}` and is resolved by replacing the context, so seeding it through `userArguments`
would silently do nothing.

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
with a `fallback-` prefixed id, because Quick AI can be a ranked hit *and* a fallback in the same
list, and two rows sharing one id would collapse in `ForEach`. That is also why `LauncherList` takes
a `selectedRowID` rather than an entry id. Nothing about a fallback row is learned, pinned or
revealed: `activate` routes to `FallbackCoordinator.run` instead of `LauncherCoordinator.launch`, and
`FallbackActionsMenu` offers only running it and opening the pane.

### User aliases

`AliasStore` (`Launcher/Service/`) keeps one user-chosen alias per entry, keyed by `preferenceKey`
like favorites and learned ranking, so every entry kind — apps, commands, quicklinks, snippets —
can carry one. An alias is deliberate in a way no vendor field is, so an exact hit is rule 1 and a
prefix hit rule 6. Only a hit **from its start** earns those rules; anywhere else the alias ranks as
an alternate title by score, so `dark` finds an alias `toggle light / dark`, while `term` inside
`iterm` never beats Terminal's own prefix. `AppIndex` reads the alias at rank time, keying its
memos on the store's revision.

A launcher row shows its entry's alias as a small chip after the name, so what a badge-bearing
result will answer to is visible without opening anything.

Editing lives in Settings only — an alias is one-time configuration like a shortcut, not a
per-invocation action, so the ⌘K menu stays out of it. Visibility is the one exception, and only in
one direction: an unwanted result is noticed while searching, so ⌘K can hide a row, but putting it
back is still the pane's checkbox. Every pane built
on `LauncherItemsSection` puts an `AliasField` on each row, dressed like the `ShortcutRecorder`
beside it; edits store as typed and trim when the field loses focus, and a blank means none. That
list filters by **membership only**, keeping the index's name order — re-ranking it per keystroke
would move the row being edited out from under its own field editor. A pane with a hand-written row
hands `AliasField` the key itself: Settings ▸ Quicklinks passes `Quicklink.entryID`, Settings ▸
Commands passes `CustomCommand.entryID`, Settings ▸ Extensions passes `extension:<name>/<command>`,
and each dims the field when the entry is hidden from launcher search, whose entry the ranker never
sees.

Aliases ride along in a settings backup (`launcherAliases`), and deleting what an alias points at —
uninstalling an app, deleting a quicklink or custom command, uninstalling an extension — removes it
with the entry's other per-entry preferences.

### Alternate names

`CFBundleAlternateNames` is how Apple names an app's other names: `iCal` for Calendar, `Address Book`
for Contacts, `System Preferences` and `Settings` for System Settings, `iBooks` for Books. They index as
alternate titles, read from the **raw** `infoDictionary`: `object(forInfoDictionaryKey:)` consults
`InfoPlist.strings`, and Calendar's replaces its `iCal` array with the string `Calendar`.
`EntryNaming.usable` (pure, covered by the harness) drops whatever repeats a name the entry already
carries and the untranslated `ALTERNATE_NAME_1` placeholders several ship.

**A row is labelled the way Finder labels it: the localized name if the bundle ships one, and
otherwise the file name.** `CFBundleDisplayName` is deliberately *not* the label — LaunchServices
ignores one that disagrees with the file name, so an app cannot present itself under a name its
folder does not carry, and neither should a launcher row. Visual Studio Code is the case that shows
it: `Code.app` would be labelled `Code`, but the folder, Finder, the Dock and the user all say
`Visual Studio Code`. Over the 83 bundles in the default scopes this rule matches
`FileManager.displayName` exactly; labelling by `CFBundleDisplayName` misses on that one.

The declared name is not thrown away — it rides along as a keyword, so `code` still finds Visual
Studio Code. Leave `Bundle.installedAppName` on
`object(forInfoDictionaryKey:)` where it is still read: forcing an English name out of `infoDictionary`
looks equivalent and is not, because FindMy's raw `Info.plist` names it `FindMy` while `Find My` lives
only in the loctable.

A loctable read costs ~0.2 ms per bundle and the scan reruns on every launcher open, so
`BundleNameCache` memoizes the names per bundle path and re-reads only when the bundle's modification
date moves. Each pass is seeded from the last and keeps only what it looked at, so uninstalled apps
fall out instead of accumulating; a changed system language drops the whole table, because the names
in it are in the old one. `SettingsPaneScanner` runs the same `BundleLocalization` walk for the
`.appex` panes, and retires its cache when either the extensions folder or the language list moves.
Headphones and Battery are named junk or nothing in every table, so their `nameOverrides` entry
replaces the walk.

## Learned ranking

`LauncherRankingStore` keeps one `LauncherVisit` per entry, keyed by `preferenceKey`: a frecency anchor,
when the entry was last opened, and its three most recent distinct search terms.

```
score(t) = max(1, e^(λ·(anchor − t)))          λ = ln 2 per 10 days
a visit: anchor = t + ln(score(t) + 100) / λ   so the score rises by 100
```

The anchor is stored rather than the score because a later anchor is always the higher score, so the
order holds as time passes and nothing is rewritten on a clock tick. An entry whose anchor has passed
scores 1, exactly like one never opened, and is pruned on load. Its search terms steer the comparator
only while the score is above 1 and the entry was opened in the last 17 days, which is what lets a
stale habit stop overriding the alignment.

Every pick through `LauncherCoordinator.launch` is a visit, with the query as it was typed: a list
click, a result, a favorite by ⌘-digit or from the compact bar, the ⌘K Open row. A global shortcut
is not a visit, and neither is a fallback or a query-driven row. A category listing records the visit
and not the word. `rank` reads the store once per pass through `snapshot()` — one clock read, not one
per candidate — and the memos key on the ranking, alias, visibility, favorites and shortcut revisions
and the sensitivity, so a launch or a reset invalidates them.

Learned data stays on device in `launcher-ranking.json`; a result that has learned ranking offers a
per-item reset in its Actions menu, and users can clear all learned ranking in General Settings.

## The empty list

Favorites, then Suggestions, then one section per kind. Each kind section is sorted by the
tiebreak, so what the user opens comes first and never-used entries still read alphabetically below
it. The sort runs within each contiguous kind run of the publication order,
so the sectioned view stays 1:1 with the flat selection.

### Suggestions

`LauncherSuggestions.select` chooses at most five from every visible entry that is not a favorite, a
meeting, an AI command or Tinycast itself. AI is the lowest priority, so Quick AI and AI Chat are
never suggested, however often they are opened:

1. up to two apps or extensions installed in the last five minutes and never opened —
   `AppEntry.installedAt` is the bundle's added-to-directory date;
2. entries with a score above 1 and no bound shortcut, in empty-list order — a shortcut is already the
   faster way in;
3. while fewer than five, built-in commands with no alias or shortcut, by
   `CommandID.suggestionPriority`: Clipboard History, Search Files, My Schedule, Search Emoji &
   Symbols, then Create Quicklink and Create Snippet. A command whose feature is off is absent from the
   index, so it is never offered.

A suggested entry leaves its kind section below, so no row appears twice. `AppIndex.Results` carries
`favoriteCount` and `suggestionCount`, which `LauncherScreen` hands to `LauncherList` for its two
leading headers. **Show suggestions** in Settings › General › Search turns the section off
(`launcherShowsSuggestions`, carried by a settings backup). `HotKeyManager.revision` is part of
`AppIndex`'s results key, because binding a shortcut takes an entry out of the section.

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
made for snippets. The feature ships off. User-defined custom sizes join the same section as their
own slice, `AppIndex.setCustomWindowSizes(_:)`, published right after the catalog. See
[window-management.md](window-management.md#custom-sizes).

## Window layouts

`WindowLayoutStore` supplies its slice the way custom commands do, sorted by name, published
immediately **before** the window commands so the two read as one family. Their per-layout shortcut
and launcher checkbox live in Settings › Window Management beside the commands', and
`windowLayoutsShowInLauncher` takes the section and its two commands out together. See
[window-layouts.md](window-layouts.md).

## Quicklinks

`QuicklinkStore` supplies its slice the same way custom commands do, sorted pinned-first then
alphabetically by `Quicklink.precedes`. Only the name is indexed — a URL is a subsequence of nearly
any query — and a per-item "show in root search" flag filters the slice before it is published. The
four Quicklinks commands are dropped from the built-in slice in the same publish while the feature is
off, so a toggle can't leave the section and its commands out of step. See
[quicklinks.md](quicklinks.md).

## Apple Shortcuts

`AppleShortcutCoordinator` reads the Shortcuts app's library through `/usr/bin/shortcuts` and supplies
it as its own slice right after Quicklinks, re-reading on every launcher open. Only the name is indexed,
and the entry id is keyed on the shortcut's UUID, so an alias or binding survives a rename in
Shortcuts. See [apple-shortcuts.md](apple-shortcuts.md).

## Custom commands

`CustomCommandStore` supplies user-authored entries to `AppIndex` without joining the off-main
application scan. Custom commands are their own alphabetized section ahead of the built-in Commands
section, and reuse fuzzy ranking, favorites, visibility, keycap rendering and the launcher's flat
selection.

Only the display name is indexed. Activation resolves the stable UUID through the store and dispatches
to `ShellCommandRunner`; see [custom-commands.md](custom-commands.md) for persistence, hotkeys and
execution semantics.

## Quick Actions

`AppEntry.Kind.quickAction` is one section holding both halves. `CommandID.fixGrammar`, `.rewrite`,
`.translate` and `.summarize` publish the shipped four while `quickActionsEnabled` is on, each
carrying the action's own title and glyph so the launcher row and the settings row can never drift.
`CommandID.init(_ action: BuiltInQuickAction)` is exhaustive, so a fifth cannot reach the launcher
without one. They report `CommandID.entryKind`, the one place a catalog command claims a section other
than Commands.

Custom actions arrive through `AppIndex.setCustomQuickActions` as `quick-action:<uuid>` entries,
sorted by when they were made, and bind `HotKeyAction.quickAction(id:)`.

Quick Actions are one of the panes in `SettingsTab.ownedCommands`, so `Enable Commands` does not reach
them. **There is deliberately no `Enable Quick Actions` category toggle** either: a
`LauncherItemsSection(kind: .quickAction)` would be a second switch over rows the pane already lists.

Activation hands the action to `QuickActionCoordinator.run(_:)` **without** hiding the palette first:
the coordinator reads the displaced app and then hides, because after the hide the frontmost app is
Tinycast. See [quick-actions.md](quick-actions.md).

## Notes commands

`CommandID.showNotes`, `.createNote`, and `.searchNotes` publish the three Notes entry points while the
feature is enabled. Activation hides the palette without restoring focus and calls the matching
`NotesCoordinator` action; each `HotKeyAction` reaches that same boundary and rechecks enablement.

`AppIndex` projects the three commands together from `notesEnabled`, independently of File Search and
Quicklinks. They represent collection actions rather than individual notes, so Notes adds no
`AppEntry.Kind` or launcher section — it owns them through `SettingsTab.ownedCommands` instead, which
is what keeps them out of Settings › Commands while they stay in the launcher's Commands section. See
[notes.md](notes.md).

## Pane-owned commands

`SettingsTab.ownedCommands` names, per pane, the commands that pane lists itself. `CommandID.owner`
inverts it once into a lookup, `CommandCatalog.makeEntry` stamps the answer onto `AppEntry.settingsOwner`,
and three places read it: `FeatureCommandsSection` draws the pane's rows from it,
`LauncherItemsSection` filters an owned row out of Settings › Commands, and `VisibilityStore` skips the
category gate for it in both `isVisible` and `allowsHotKey`. Stamping the entry rather than sniffing its
id is what keeps "which pane owns this" out of the entry-ID namespace.

Eleven panes own commands today — AI, Quick Actions, File Search, Notes, Snippets, Navigation,
Window Management, Clipboard, Emoji, Calendar and Quicklinks. What is left in Settings › Commands is
the set no feature switch governs: Calculator History, Open Camera, the three backup commands, Check
for Updates, Tinycast Settings, About, Support and Quit.

A pane's list is also its display order, so `CommandID`'s declaration order is grouped by owner.
Nothing keys on that order — `CommandCatalog.all` sorts by name and every preference keys on the raw
value — so a command may be moved between owners without migrating anything.

## Navigation commands

`CommandID.switchWindows` opens every running app's windows as a palette screen, and
`CommandID.searchMenuItems` does the same for the front app's menu bar. Both are plain command
entries — no new `AppEntry.Kind` and no `VisibilityStore` category — owned by Settings › Navigation
through `SettingsTab.ownedCommands`, so `navigationEnabled` is their switch. Their invariants and
internals live in [navigation.md](navigation.md) and [menu-search.md](menu-search.md).

> **Invariant:** `Tests/fuzz-test.swift` compiles the real `Launcher/Model/LauncherMatch.swift` and
> `LauncherOrder.swift`, so both must stay Foundation-only and pure. There is no copy of the ranking
> to keep in sync.

The ranking harness covers the frecency curve, search-term retention and its 17-day gate, pruning,
persistence and both reset paths; see the command in `development.md`.

Launcher rows and compact favorites ask for the point size they actually draw at, scaled by the
view's `displayScale`: 24/26/29pt becomes 48/52/58px at 2×. `IconCache` still rasterizes through its
96px canvas first — AppKit picks the representation and the drop shadow from that size — and then
keeps only the row-sized bitmap, in an 8 MB cost-capped row cache separate from the 32 MB one.

That cache holds **one size per path and stamp**: switching interface size replaces each entry
rather than accumulating all three. A lookup carrying a different size is a miss, so a row can never
paint a bitmap meant for another layout. Everything else — settings, symbols, artwork — keeps the
96px path and the persistent 32 MB cache. Fitted file-row icons keep their own transient 8 MB cache,
purged when its palette list disappears.

A file-icon key carries a `FileIconStamp` as well as the path — the bundle's own modification and
attribute dates plus its `Icon\r` — because pasting a custom icon in Finder leaves the bundle's
contents alone, so a path-only key served the bitmap decoded first for the rest of the session.
`AppIndex.scan` reads the stamp off-main into `AppEntry.iconStamp`, `EntryIcon.file` carries it, and
because it is part of `iconKey` the re-scan on the next palette open re-decodes exactly the apps
whose icon moved.

## Favorites

`FavoritesStore.keys` is the order — the array *is* the ranking, and it only shows while the query is
empty, where `AppIndex.orderedResults` pins it as a prefix of the results and counts it in
`Results.favoriteCount`. `LauncherScreen` reads that count once in `init`, and the list, the reorder
rows and the chord guards all read that one number, so the visible section and what a move acts on
can't disagree.

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
which a re-show that preserves state skips entirely. The flag flips **400 ms after** the press, not
on it: every ⌘ chord in the palette starts as a ⌘ press, so revealing on the down edge flashed the
numbering under ⌘↵ and ⌘K. `noteCommandHeld` schedules the reveal and any release cancels it, so a
chord's own tap never outlives its keystroke while a deliberate hold still lights every row. **`AppRow` observes that flag itself**: reading
it any higher would attach it to `RootPaletteView`'s body and rebuild the whole palette on every ⌘
press, where a row-level read re-runs only the handful of rows the `LazyVStack` has realized. The
digit each row shows is carried on its `Row` case from the section build, so no row searches for its
own position.

## Hiding one result

**Hide from Search**, on a result's ⌘K menu and on **⇧⌘H**, writes exactly what the checkbox in
Settings writes — `VisibilityStore.setItemVisible(false,…)` against the entry's `preferenceKey` — so
the row leaves
every search until that checkbox is ticked again. Nothing else moves: the app stays installed, its
favorite, alias and learned ranking survive the round trip, and its shortcut keeps firing, because
`allowsHotKey` gates by category and never by item.

The row is offered only where Settings can undo it, and `KindDescriptor.canHideFromSearch` is that
rule — per kind, and a new `Kind` case has to answer it to compile. Applications, System Settings,
Commands, Quick Actions, System Actions, Window Commands, Window Layouts and extension commands each
draw a per-row checkbox in their pane, so they carry it. Custom commands, quicklinks and snippets do
not: their panes list a record with its own switches, not a launcher checkbox — a hide nothing in
Settings can visibly undo is a trap, not a shortcut.
`AppActionsMenu` adds the query-driven guard the favorites row already uses: a typed URL lives only
for its query and has no preference to write.

Hiding shrinks the list under the action that ran it, so `LauncherScreen.hideFromSearch(at:)`
re-reads the order and drops the highlight into the index the row vacated, clamped to what is left —
the move `selectFavorite` already makes. The palette stays open on the same query, with focus
untouched. One function answers both the menu row and the chord, and it re-tests eligibility rather
than trusting the caller, so ⇧⌘H falls through to whatever else wants the press on a row that offers
no such menu item.

## Reveal in Finder

Application and System Settings results expose **Show in Finder** in their ⌘K Actions menu and on
**⌘↵**. Synthetic command results have no filesystem location, so neither the menu row nor the
shortcut is available for them. `AppEntry.canRevealInFinder` is the one rule both the menu row and
the key handler read, so the advertised chord can't drift from the behavior.

## Dragging an application out

An application row drags its bundle onto the Dock, into a System Settings privacy list, or anywhere
else that takes an app. `AppEntry.canDragOut` — `KindDescriptor.canDragOut`, true for `.application`
alone — is the one rule: a Settings pane or a shortcut dropped on another app opens nothing there,
and every new kind has to say so to build.

The row uses `onRowTap(drag:)` from `DesignSystem/Interaction/RowClick.swift`, the tap-shaped sibling
of the clipboard's and File Search's `onRowClick(drag:)`. A launcher click launches rather than
selects, so the press **activates on the release** — the one moment a press is known not to have
become a drag. A row that cannot drag gets plain `onTapGesture`, so every other kind, the fallbacks
and the lead card keep SwiftUI's own gesture. The operation is **copy only**, as
[clipboard.md](clipboard.md#dragging-out) explains: on the boot volume a file-URL drag would default
to a move, and moving an app out of `/Applications` is never what a launcher should do. The image is
the shared icon bitmap when it is warm and `NSWorkspace`'s otherwise, never a decode, and a landed
drop hides the palette through `PaletteCoordinator.dragLanded()`. Compact mode's favorite buttons do
not drag.

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
