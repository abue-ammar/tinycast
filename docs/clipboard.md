# Clipboard history

## Poll-based capture

`ClipboardManager` runs a 0.5s `Timer` watching `NSPasteboard.general.changeCount`. To avoid
re-capturing Tinycast's own writes, every write stamps a private `internalType` marker on the
pasteboard and the poller skips anything carrying it.

## Store

`ClipboardStore` is SQLite-backed: rows plus a trigram FTS5 index in `clipboard.sqlite3`, with image
blobs as loose PNG files, all under `~/Library/Caches/<bundle-id>/`. The newest 1000 rows are mirrored
in the `@Published items` window; FTS search reaches older rows.

A database that won't open is deleted and recreated (worst case the store degrades to session-only
in-memory history).

Image capture (TIFF→PNG re-encode + blob write) runs off the main actor via detached tasks; row
inserts, search, and pruning stay on the main actor.

## Pinned entries

A row's ⌘K Actions menu carries **Pin Entry / Unpin Entry** (⌘P), persisted as a `pinned` column on
`items` (added to existing databases by an `ALTER TABLE` migration, alongside `source_app`'s).

Pins change three things:

- **Order.** `search` returns pinned rows first — for the empty query and for FTS hits alike — each
  block still newest-first, so the list renders them under one "Pinned" section above the date
  buckets. `items` itself stays in pure recency order; the display split is memoized next to the
  search memo and invalidated with it.
- **Retention.** Pruning skips pinned rows (`AND pinned = 0`), so a pin outlives the retention
  window; the in-memory window keeps every pinned row too (`load` fetches all of them plus the
  newest 1000 unpinned, and the trim never drops a pin). "Clear History" still deletes everything.
- **Selection.** Pinning lifts a row out of its date bucket, so `AppCore.togglePinnedClip` moves the
  palette selection to the row's new index in the *current* results and bumps `palette.followToken`,
  which is what makes the list scroll the highlight back into view.
