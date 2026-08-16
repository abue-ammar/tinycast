# Clipboard history

## Invariants

- **Clipboard writes stamp a private `internalType` marker** so the poller skips Tinycast's own writes.
  If the writer and the poller ever disagree, the app re-captures its own pastes in a loop.
- **`Model/ClipboardStore.swift` keeps to Foundation plus SQLite3 and no other app source**, so
  `clipboard-test` can compile it standalone. It uses `isolated deinit` for its SQLite teardown.
- A database that cannot be opened is deleted and recreated. That is only sound because history is
  regenerable — `QuicklinkStore` deliberately does the opposite.
- **A link or an address is derived from the text, never persisted.** `ClipboardItem.Kind` stays
  `text`/`image` — the two things capture can tell apart — so improving the classifier is a code
  change rather than a database migration plus a backfill.

## Poll-based capture

`ClipboardManager` runs a 0.5s `Timer` watching `NSPasteboard.general.changeCount`. To avoid
re-capturing Tinycast's own writes, every write stamps a private `internalType` marker on the
pasteboard and the poller skips anything carrying it.

## Store

`ClipboardStore` is SQLite-backed: rows plus a trigram FTS5 index in `clipboard.sqlite3`, with image
blobs as loose PNG files, all under `~/Library/Caches/<bundle-id>/`. The newest 1000 rows are mirrored
in the observable `items` window; FTS search reaches older rows.

A database that won't open is deleted and recreated (worst case the store degrades to session-only
in-memory history).

Image capture (TIFF→PNG re-encode + blob write) runs off the main actor via detached tasks; row
inserts, search, and pruning stay on the main actor.

**The load query is deliberately two indexed branches**, not one `pinned_at IS NOT NULL OR rowid >= ?`.
It fetches every pinned row plus the newest `memoryWindow` unpinned ones, keyed off the floor rowid
that `windowFloor` looks up. The planner cannot drive an `OR` from an index while preserving row
order, so the single-predicate form reads the whole table instead. The floor is 0 — meaning no floor,
load everything — while the history is shorter than the window.

Searching is trigram FTS, which needs **at least three characters**; shorter queries, and the
no-database fallback path, filter the in-memory window instead. Results are memoized one query deep,
with a second memo for the empty query, and both are invalidated whenever `items` changes.
`promote` rewrites a row under the same id so it leads the history — stored order is rowid, so it is a
delete plus re-insert inside one transaction, since `id` is `UNIQUE` and a crash between the two
statements must not lose the row. The image blob is never touched.

Files under the store's own `imagesDir` are **owned**: pruned and deleted with their row. External
references — an image imported from another app's cache — are left on disk when the row goes. A
retention cut can strand hundreds of files, so those deletions run off the main actor to keep
capture-time pruning from hitching.

## Type filter

The clipboard header carries a `ClipboardFilterButton` at the trailing edge of the search field —
the only palette screen with a control up there. It toggles a `PopoverMenu` anchored `.topTrailing`
under the button, so the ⌘K Actions menu, the app menu and this one are the same view on the same
glass. **⌘P** toggles it; ↑/↓, ↵ and Esc come free from `RootPaletteView`'s one menu path, and the
menu opens highlighting the *active* filter rather than the first row, the way a pop-up button does.
The filter is not gated on the list having rows: an over-narrow filter empties it, and the button is
the way back out.

`ClipboardFilter` owns the five cases and everything the UI needs from them — title, glyph, and the
`emptyMessage` that stops "Clipboard history is empty" from appearing over a history that only looks
empty. The cases are **exclusive**: a copied URL is a link, not a narrower kind of text, so *Text
Only* means prose.

`ClipboardItem.textForm` derives `plain`/`link`/`email` from the text on demand — nil for an image.
The classifier is guarded cheapest-first, because `rows` is rebuilt every render: anything over
2048 UTF-8 bytes is plain by definition (`utf8.count` is O(1), `count` walks graphemes), then
anything holding whitespace, then a `scheme://` or `mailto:` prefix, an address shape, and finally
a bare domain. That last step is the only one needing judgement — `report.pdf` and `index.html` are
domain-shaped — so a bare domain must be lower case (which is what keeps `Safari.app` out) and end
in one of a compact set of TLDs people actually copy. It is a heuristic whose worst case files a row
under the wrong type, and `clipboard-test` pins the cases that matter.

`search(_:filter:)` filters **after** the pinned/rest split, so a matching pin still leads its block
in pin order, and the filter joins the search memo's key — keying on the query alone would serve
stale rows for a render or more, since the filter changes without the query moving. One consequence
of filtering after the fact: the FTS statement's `LIMIT 200` applies to the *unfiltered* matches, so
a narrow filter over a broad query can show fewer rows than the history holds.

## Pinned entries

A row's ⌘K Actions menu carries **Pin Entry / Unpin Entry** (⌘., since ⌘P opens the type filter),
persisted as a `pinned_at` column
on `items` (added to existing databases by an `ALTER TABLE` migration, alongside `source_app`'s) —
a stamp rather than a flag, because the Pinned section is ordered by _when you pinned_, not by
recency.

Pins change four things:

- **Order.** `search` returns pinned rows first — for the empty query and for FTS hits alike — under
  one "Pinned" section above the date buckets, in pin order with the oldest pin at the top, so a new
  pin joins the end of the section instead of displacing the ones already there. `items` itself stays
  in pure recency order; the display split is memoized next to the search memo and invalidated with
  it. Pinned rows are matched **in memory**
  rather than taken from the FTS result, since the statement's `LIMIT` could otherwise drop one out
  of a busy query's matches — which holds because every pinned row is resident in `items`, however
  old (`load` fetches them all, and neither the window trim nor pruning drops one).
- **Unpinning re-recencies.** An unpinned row rejoins the history as its _newest_ entry (Raycast does
  the same) rather than dropping back into the date bucket it came from, which would scroll the list
  out from under the selection. It's the same delete + re-insert `promote` uses.
- **Retention.** Pruning skips pinned rows (`AND pinned_at IS NULL`), so a pin outlives the retention
  window. "Clear History" still deletes everything.
- **Selection.** Pinning lifts a row out of its date bucket, so `ClipboardCoordinator.togglePinnedClip` moves the
  palette selection to the row's new index in the _current_ results and bumps `palette.followToken`,
  which is what makes the list scroll the highlight back into view.

Pasting a pinned entry deliberately does **not** promote it: it holds its place in the Pinned
section, so `promote` skips pinned rows instead of rewriting the row and its FTS entry for no
visible change.

`load` reads every pinned row plus the newest 1000 unpinned ones as two indexed branches over a
partial index on `pinned_at` (`Tests/clipboard-test.swift` covers the shape). The single
`pinned_at IS NOT NULL OR rowid >= ?` form reads better but cannot be driven from an index while
holding row order, so it scans the whole table — ~12ms against ~1ms at 200k rows, on the main actor
at launch.
