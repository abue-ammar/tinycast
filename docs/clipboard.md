# Clipboard history

## Poll-based capture

`ClipboardManager` runs a 0.5s `Timer` watching `NSPasteboard.general.changeCount`. To avoid
re-capturing Smallcast's own writes, every write stamps a private `internalType` marker on the
pasteboard and the poller skips anything carrying it.

## Store

`ClipboardStore` is SQLite-backed: rows plus a trigram FTS5 index in `clipboard.sqlite3`, with image
blobs as loose PNG files, all under `~/Library/Caches/<bundle-id>/`. The newest 1000 rows are mirrored
in the `@Published items` window; FTS search reaches older rows.

A database that won't open is deleted and recreated (worst case the store degrades to session-only
in-memory history).

Image capture (TIFF→PNG re-encode + blob write) runs off the main actor via detached tasks; row
inserts, search, and pruning stay on the main actor.
