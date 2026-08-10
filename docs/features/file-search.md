# Search Files

Search Files is an on-demand palette screen for opening files and folders from visible top-level home
folders and cloud-storage roots. It searches filenames through Spotlight, adds no private index or
launch work, and is reached from the built-in Search Files launcher command.

## Invariants

- **Every Spotlight query is capped at 1,000 candidates before execution, and 200 rows after filtering.**
  `MDQuerySetMaxCount` is the reason the
  feature uses `MDQuery`; `NSMetadataQuery` has no source-result cap and can break the 100 MB budget on
  a broad filename. See [decisions.md](../decisions.md) entry 33.
- **`Model/FileSearchResult.swift` and `Model/FileSearchQuery.swift` stay Foundation-only and pure.**
  `file-search-test` compiles the shipped files together with the existing pure fuzzy scorer.
- **Search is filename-only and on demand.** Visible home folders and cloud roots are searched;
  `~/Library`, hidden paths, app bundles and generated trees are not. An empty query does no work and
  Tinycast creates no content index, history, cache, watcher or search data.
- **Tinycast asks for no file permission.** Hidden metadata items and application bundles are filtered,
  and Spotlight or TCC omissions produce a thinner result set rather than a prompt for Full Disk Access.
- **A superseded query never publishes.** The session cancels its pending task and checks cancellation
  after the synchronous Spotlight call, so a late result cannot replace the newer query's rows.

## Query path

`FileSearchQuery` trims and tokenizes input on whitespace, escapes Spotlight metacharacters, and builds
one `kMDItemFSName` clause per term. The clauses are joined with AND, so `annual report` requires both
words in the filename without requiring them to be adjacent or in that order.

`FileSearchSession.search` retains the previous rows, debounces for 120 ms, then drives
`FileSearchService.search` in a detached user-initiated task. The service shallowly enumerates home to
find visible top-level directory scopes and direct files, adds the current cloud-storage roots, then
keeps the `MDQuery` reference inside one nonisolated synchronous function. Spotlight returns at most
1,000 candidates. `FileSearchQuery` removes hidden path components, app-bundle contents and exact
directory components named `node_modules`, `DerivedData`, `build`, `dist`, `target` or `Pods`, then
applies `FuzzyMatch` and publishes at most 200. Localized filename then path order makes ties deterministic.

Visible files and document packages directly under home are matched locally with the same case- and
diacritic-insensitive all-terms rule. `~/Library` is never a general scope; only `CloudStorage` and the
current iCloud Drive root are admitted from it.

The synchronous API can finish after its surrounding task is cancelled. That work is bounded and its
result is discarded: `Task.checkCancellation()` and the session's current-query check both run before
publication. Leaving or hiding the screen cancels and clears the session as well.

`FileSearchService.search` emits a `FileSearchService.search` interval on the shared
`com.tinycast.perf` signpost subsystem. `Tests/file-search-performance.swift` exercises the same service
against the current user's Spotlight index and reports first-run and repeated-query latency; it stays
outside `run-tests.sh` because filesystem contents and Spotlight state are machine-dependent.

The 2026-08-10 baseline used a release-optimized standalone process against the developer home. Across
`a`, `e`, `swift`, `pdf` and `project`, first runs took 598–701 ms, repeated medians took 612–703 ms and
the process reached 27 MB maximum RSS. The palette's debounce adds 120 ms before that measured service
interval. These are local orders of magnitude, not budgets; rerun the benchmark after query-policy work.

## Palette and actions

`FileSearchScreen.rows` is the exact flat selection order rendered by `FileSearchList`. The list uses
the shared Results header, row metrics, edge dissolve, thin scrollbar and scroll intent. A row shows a
fitted native file icon, the full filename, and its tilde-abbreviated parent path.

- Return calls `FileSearchCoordinator.open`, hides the palette without restoring focus, and uses the
  asynchronous `NSWorkspace` configuration API. A failure goes through Tinycast's dialog controller.
- Command-Return reveals the item in Finder and dismisses the palette.
- Copy Path writes the standardized path through `Paster`, leaves the palette open, and reports through
  the message HUD.

The empty screen runs no query. The first in-flight query says "Searching files…", an empty completed
query says "No files found", and query creation or execution failure says
"File search is unavailable" inline.

## Invocation

`CommandID.searchFiles` is an ordinary built-in command that switches the palette to `.fileSearch`.
It deliberately has no `HotKeyAction`, global shortcut, Settings control or persisted state.
