# Search Files

Search Files is an on-demand palette screen for opening files and folders from the folders the user
configures. It searches filenames through Spotlight, adds no private index or launch work, and is
reached from the built-in Search Files launcher command — or its own global shortcut — after the
feature is enabled in Settings.

## Invariants

- **Every Spotlight query is capped at 1,000 candidates before execution, and 200 rows after filtering.**
  `MDQuerySetMaxCount` is the reason the
  feature uses `MDQuery`; `NSMetadataQuery` has no source-result cap and can break the 100 MB budget on
  a broad filename.
- **Everything under `Model/` stays Foundation-only and pure**, `FileSearchIgnoreList`'s `import Darwin`
  included. `file-search-test` compiles the shipped files together with the existing pure fuzzy scorer.
- **Search is filename-only and on demand.** An empty query does no work and Tinycast creates no
  content index, history, query cache, watcher or search data.
- **Hidden paths and application-bundle contents are structural, not patterns.** They are what keeps
  the feature permission-free, so no user setting can re-admit them. Everything else that is dropped
  comes from the ignore list.
- **`~/Library` is never a scope Tinycast picks by itself.** A configured home root expands into its
  visible children plus the two cloud-storage roots instead. A user who adds a folder under `~/Library`
  by hand gets what they asked for.
- **The shipped ignore rules are compiled in and never persisted.** `fileSearchIgnorePatterns` stores
  only what the user added, so changing `FileSearchIgnoreList.defaults` reaches installs that already
  ran. The consequence is that the shipped six cannot be switched off.
- **File Search is off by default, and off means no entry point or Spotlight work.** A nonempty query
  on that screen is the first operation that searches, and the global shortcut no-ops while the
  feature switch is off.
- **Tinycast asks for no file permission.** Hidden metadata items and application bundles are filtered,
  and Spotlight or TCC omissions produce a thinner result set rather than a prompt for Full Disk Access.
- **A superseded query never publishes.** The session cancels its pending task and checks cancellation
  after the synchronous Spotlight call, so a late result cannot replace the newer query's rows. Editing
  the scopes or the patterns cancels the session for the same reason: a result found under the old
  rules must not land under the new ones.

## Query path

`FileSearchQuery` trims and tokenizes input on whitespace, escapes Spotlight metacharacters, and builds
one `kMDItemFSName` clause per term. The clauses are joined with AND, so `annual report` requires both
words in the filename without requiring them to be adjacent or in that order.

`FileSearchSession.search` retains the previous rows, debounces for 120 ms, then drives
`FileSearchService.search` in a detached user-initiated task. One worker serializes synchronous
Spotlight calls and coalesces changes to the newest pending query, so slower typing cannot accumulate
overlapping queries. The service resolves the configured roots, then
keeps the `MDQuery` reference inside one nonisolated synchronous function. Spotlight returns at most
1,000 candidates. `FileSearchQuery` removes hidden path components and app-bundle contents, applies the
ignore list, then applies `FuzzyMatch` and publishes at most 200. Localized filename then path order
makes ties deterministic.

Visible files and document packages directly under home are matched locally with the same case- and
diacritic-insensitive all-terms rule, since scoping Spotlight to home itself would pull in `~/Library`.

## Scopes and ignore patterns

`FileSearchPolicy` is the resolved answer to "what does this scope list mean": it splits the configured
roots into the ones Spotlight takes verbatim and the home root that has to be expanded, and it compiles
the ignore list. It is rebuilt when either setting changes, never per keystroke, so glob compilation and
tilde expansion stay off the typing path.

Scopes are stored tilde-abbreviated in `fileSearchScopes` so a backup taken on one machine still points
somewhere on another. Home expands into its visible children plus `Library/CloudStorage` and the current
iCloud Drive root; every other root is handed to `MDQuerySetSearchScope` as it stands. An empty list
searches nothing rather than falling back to home — a cleared list is a deliberate choice, not an unset one.

`FileSearchIgnoreList` compiles each pattern once into one of three buckets, which is what keeps matching
cheap enough to run against every candidate:

| Pattern shape | Matched against | Example |
| --- | --- | --- |
| no `/`, no metacharacters | any path component, case-folded, via a `Set` | `node_modules` |
| no `/`, has `*` `?` `[` | any path component, via `fnmatch` | `*.tmp` |
| contains `/` | the whole absolute path, via `fnmatch` | `**/[Cc]ache/**` |

`fnmatch` runs with `FNM_CASEFOLD` and deliberately **without** `FNM_PATHNAME`, so `*` spans `/` and a
`**/…/**` pattern behaves as written. Patterns are stored pre-terminated as `ContiguousArray<CChar>`, so
the hot path never re-encodes a `String` into a temporary C buffer.

Bare `*` name globs are also pushed into the Spotlight expression as `kMDItemFSName != "…"cd` clauses, so
ignored files cannot consume the 1,000-candidate cap. Only that shape is pushed: Spotlight reads `?` and
`[` literally, and `kMDItemPath` is not queryable at all, so path globs have no server-side spelling and
stay local. Quotes and backslashes are escaped on the way in, and any pattern still carrying one is kept
out of the expression — an unescaped pattern would otherwise nil `MDQueryCreate` and break every search
until it was deleted.

The synchronous API cannot stop mid-call. A superseded result is discarded through the session's
revision check, then the same worker runs only the newest pending query. Leaving or hiding the screen
cancels and clears the session as well.

`FileSearchService.search` emits a `FileSearchService.search` interval on the shared
`com.tinycast.perf` signpost subsystem. `Tests/file-search-performance.swift` exercises the same service
against the current user's Spotlight index and reports first-run and repeated-query latency; it stays
outside `run-tests.sh` because filesystem contents and Spotlight state are machine-dependent.

The 2026-08-11 baseline used a release-optimized standalone process against the developer home. Across
`a`, `e`, `swift`, `pdf` and `project` on the shipped settings, first runs took 192–831 ms, repeated
medians took 191–668 ms and the process reached 26 MB maximum RSS. The benchmark runs every query twice,
once on the shipped rules and once with five extra user patterns, and the second pass costs 5–10 ms more
— so pattern matching is not where the time goes, and the two broad single-letter queries dominate
either way. The palette's debounce adds 120 ms before that measured service interval. These are local
orders of magnitude, not budgets; rerun the benchmark after query-policy work.

## Palette and actions

`FileSearchScreen.rows` is the exact flat selection order rendered by `FileSearchList`. The list uses
the shared Results header, row metrics, edge dissolve, thin scrollbar and scroll intent. A row shows a
fitted native file icon, the full filename, and its tilde-abbreviated parent path.

Fitted row icons use a separate 8 MB transient cache. Leaving the list or hiding the palette purges it
and invalidates in-flight decodes, so scrolling stays warm within one result set without retaining its
icons after File Search closes. Persistent launcher icons remain in their own cache.

- Return calls `FileSearchCoordinator.open`, hides the palette without restoring focus, and uses the
  asynchronous `NSWorkspace` configuration API. A failure goes through Tinycast's dialog controller.
- Command-Return reveals the item in Finder and dismisses the palette.
- Copy Path writes the standardized path through `Paster`, leaves the palette open, and reports through
  the message HUD.

The empty screen runs no query. The first in-flight query says "Searching files…", an empty completed
query says "No files found", and query creation or execution failure says
"File search is unavailable" inline.

## Invocation

Settings ▸ File Search owns the `fileSearchEnabled` switch, which is off when its preference is absent,
along with the scope list, the ignore patterns and the Search Files command row. All of them are
ordinary settings carried by Tinycast settings backups; importing them grants no permission or
background access.

`AppCore` observes the switch and asks `FileSearchCoordinator` to project `CommandID.searchFiles` into
the launcher; a second observation rebuilds the policy when either list changes. The coordinator also
guards entry into `.fileSearch`, so neither a stale selected command nor the global shortcut can open
the screen after the feature is disabled. Disabling cancels the session and returns an open File Search
screen to the launcher without changing palette visibility.

Search Files is the only built-in command with a `HotKeyAction` of its own, so `AppEntry.hotKeyAction`
returns non-nil for it alone. Two consequences follow: its launcher row prints the chord as a keycap,
and the Search Files row in Settings ▸ Commands carries the same recorder as the one in this pane —
one binding reachable from two places, not two settings.

Launcher visibility is `VisibilityStore`'s, keyed on the entry's `preferenceKey`, which is why the
pane's checkbox and the one in Settings ▸ Commands move together. The entry behind it comes from
`CommandCatalog.entry(for:)` rather than `AppIndex`, because the index drops the command entirely while
the feature switch is off — exactly when the pane still has to draw the row. Hiding the command leaves
the shortcut working, as it does for every other feature.
