# Clipboard history

## Invariants

- **`clipboardEnabled` ships on — the only feature switch that does.** Absence of the key therefore
  has to outrank a stored `false` in `AppSettings.init`, and off means fully off: the poller stops,
  the SQLite file closes, the launcher command and its shortcut go, and Tab skips the screen.
  `ClipboardCoordinator.applyEnabled()` is the single place that applies it.
- **Clipboard writes stamp a private `internalType` marker** so the poller skips Tinycast's own writes.
  If the writer and the poller ever disagree, the app re-captures its own pastes in a loop.
- **`Model/ClipboardStore.swift` keeps to Foundation plus SQLite3 and no other app source**, so
  `clipboard-test` can compile it standalone. It uses `isolated deinit` for its SQLite teardown.
- A database that cannot be opened is deleted and recreated. That is sound because a history is
  captured rather than authored, and there is no UI for an unavailable clipboard — `QuicklinkStore`
  deliberately does the opposite. It is **not** a licence to treat the file as disposable: it lives in
  Application Support precisely because nothing else can put it back.
- **A link or an address is derived from the text, never persisted.** `ClipboardItem.Kind` holds
  only what capture can tell apart on the pasteboard — `text`, `image`, `file` — so improving the
  *classifier* stays a code change rather than a database migration plus a backfill, while a new
  kind needs a new pasteboard type to justify it. `textForm` is nil for anything but `.text`, which
  is what keeps a path shaped like `apple.com/report.pdf` out of the links.
- **A `.file` entry references the file where it lies and never copies it.** Its absolute path is
  the `text` column, so the trigram index finds it by name or by folder for free, and `imagePath`
  stays nil — which is what keeps `prune`, `deleteBlob` and `owns` from ever reaching a file
  Tinycast did not write. `kind` is a plain `TEXT` column, so the case cost no migration; an older
  build simply fails to decode the row.
- **A colour is parsed from the text on demand, never stored.** `ColorValue` is the single parser
  behind the clipboard's swatches and the launcher's colour card, so the two can never disagree
  about what counts as a colour or what it converts to.

## Poll-based capture

**A file URL is read before the text**, because that is the whole of the bug this ordering fixes:
Finder puts the file's *display name* on `public.utf8-plain-string` beside `public.file-url`, so a
text-first poller records `IMG_1234.png` as prose. The read sits after the `internalType` and
sensitive-type guards, which stay unconditional — a secret must never be recorded whatever shape it
arrives in. A bare screenshot carries no file URL and still falls through to the `.png`/`.tiff`
branch untouched.

`ClipboardManager.fileURLs(on:volatileRoots:)` takes both the pasteboard and the roots as
parameters, so `pasteboard-test` can drive an `NSPasteboard.withUniqueName()` and its own scratch
tree: a harness that touched `NSPasteboard.general` would land in the reader's own running Tinycast
as a genuine copy. It reads with `urlReadingFileURLsOnly`, so a copied `http` URL stays a link;
returns nil rather than an empty array, so the text branch runs; caps a batch at
`maxCapturedFiles`, so a Finder select-all cannot insert ten thousand rows on one tick; and
**rejects a file under a volatile root** (`/tmp`, `/var/folders`, `~/Library/Caches`), because an
app that stages a temp export beside better inline content must keep the inline content. Paths come
back reversed so the *first* file copied ends up leading the history.

`ClipboardManager` runs a 0.5s `Timer` watching `NSPasteboard.general.changeCount`. To avoid
re-capturing Tinycast's own writes, every write stamps a private `internalType` marker on the
pasteboard and the poller skips anything carrying it.

`stop()` is the off switch: it drops the timer and the fast-user-switching observers, and clears the
`isCapturing` flag that `prepareForTinycastPasteboardMutation` reads — so a paste Tinycast performs
itself no longer drains the pasteboard into history either.

Existing clips survive being switched off, since a history is captured rather than authored and
nothing else can put it back. **Clear history stays live with the feature off** —
`ClipboardCoordinator.clearHistory()` reopens the file, empties it and closes it again — so a reader
who turns the feature off can still erase what it kept.

## Store

`ClipboardStore` is SQLite-backed: rows plus a trigram FTS5 index in `clipboard.sqlite3`, with image
blobs as loose PNG files, all under `~/Library/Application Support/<bundle-id>/`. The newest 1000 rows
are mirrored in the observable `items` window; FTS search reaches older rows.

**Application Support, not Caches.** `~/Library/Caches` is excluded from Time Machine and the system
may reclaim it at any time without telling the app, so a history kept there survives neither a restore
nor a full disk — while the retention setting offers **Forever** and a pin is an explicit act.

A database that won't open is deleted and recreated (worst case the store degrades to session-only
in-memory history).

Image capture (TIFF→PNG re-encode + blob write) runs off the main actor via detached tasks; row
inserts, search, and pruning stay on the main actor.

**A backup reads the whole table, not `items`.** `forEachStoredItem(inDatabaseAt:)` is `nonisolated`
and opens a second connection, because the resident window stops at 1000 rows while the table is
capped only by age — an export that read `items` would silently drop the rest of someone's history,
and walking an uncapped table is not main-actor work. That connection is `SQLITE_OPEN_READWRITE`,
not read-only: a read-only connection to a WAL database still has to create its `-shm` file, and
fails confusingly when it cannot. It reads in `rowid` order, oldest first, so a streaming
import rebuilds the same order it exported.

**A restore streams back the same way.** `importStoredItems(inDatabaseAt:adoptingImagesInto:_:)` is the
one insert path a bulk import takes, `importEntries` included: it hashes the existing rows once into a
dedupe set rather than scanning the table per candidate, holds one transaction, and moves a staged blob
into `imagesDir` only once the row is known to be new. `adoptingImagesInto` is nil where the paths
handed in are already the ones to keep, as the Raycast import's are.

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

`ClipboardFilter` owns the seven cases and everything the UI needs from them — title, glyph, and the
`emptyMessage` that stops "Clipboard history is empty" from appearing over a history that only looks
empty. The cases are **exclusive**: a copied URL is a link, not a narrower kind of text, so *Text
Only* means prose, and *Colors Only* takes `#FF5733` out of it.

`ClipboardItem.textForm` derives `plain`/`color`/`link`/`email` from the text on demand — nil for an
image.
The classifier is guarded cheapest-first, because `rows` is rebuilt every render: anything over
2048 UTF-8 bytes is plain by definition (`utf8.count` is O(1), `count` walks graphemes), then
a colour, then anything holding whitespace, then a `scheme://` or `mailto:` prefix, an address
shape, and finally a bare domain. Colour runs **before** the whitespace reject, because
`rgb(255, 87, 51)` is one value that happens to be written with spaces in it — every later branch
is a single token by definition. That last step is the only one needing judgement — `report.pdf`
and `index.html` are
domain-shaped — so a bare domain must be lower case (which is what keeps `Safari.app` out) and end
in one of a compact set of TLDs people actually copy. It is a heuristic whose worst case files a row
under the wrong type, and `clipboard-test` pins the cases that matter.

`search(_:filter:)` filters **after** the pinned/rest split, so a matching pin still leads its block
in pin order, and the filter joins the search memo's key — keying on the query alone would serve
stale rows for a render or more, since the filter changes without the query moving. One consequence
of filtering after the fact: the FTS statement's `LIMIT 200` applies to the *unfiltered* matches, so
a narrow filter over a broad query can show fewer rows than the history holds.

## Colours

A copied colour is drawn as the colour and can be copied back out in another notation. Two
surfaces read one parser: the clipboard history, and the launcher, where pasting a colour answers
with a card the way the calculator does.

`ColorValue` (`Model/`, Foundation-only) is that parser. It takes the CSS spellings people copy —
the four hex lengths, plus `rgb()`/`hsl()` and their alpha forms in both the comma and CSS4
space-and-slash syntax — and stores **sRGB components**, so every notation derives from one source
rather than a second parser that can drift from it.

**A colour is rejected rather than approximated**, because a wrong swatch filed under Colors Only
is worse than none. An HSL channel must carry its `%`, or `hsl(120, 100, 50)` clamps to white.
Arguments are counted, so `rgb(255,,87,51)` is malformed rather than three good ones with a hole;
each side of a `/` is counted separately, or `rgb(0 255 / 0.5)` reads an alpha as its blue channel.
`Double` also parses `nan`, `inf` and Swift literals CSS never writes, and every notation ends in
an `Int(_:)` that traps on a non-finite value — so the reject sits at the parse boundary.

`ColorFormat` offers four notations: hex, `rgba()`, `hsl()` and `oklch()`, plus the two spellings
named for their alpha, which `offered(for:)` drops from an opaque colour — six rows at most, four
for an opaque one. The digits themselves are `ColorDigits`, private to that file: writing a colour
is the format's business, not the value's. The rest of CSS Color 4 — the space-separated forms,
`hwb()`, `lab()`, `lch()`, `oklab()` — and the `NSColor`/`UIColor`/SwiftUI spellings were all built
and then removed: they
restate the same four answers, and a row you scroll past to reach the one you wanted costs more
than it gives. `oklch()` stays as the one perceptual space people write, and `hsl()` keeps one
decimal because whole degrees cost up to 5/255 on the way back. `clipboard-test` sweeps every
offered notation and re-parses it.

`ColorSpaces.swift` holds Oklab and its polar form — matrices and cube roots, no tables. Oklab is
private to it: `oklch()` is the one thing it exists for. A neutral is stated with no hue at all,
since `atan2` over two rounding errors still names a direction.

The notations are a menu of their own under the launcher card, and **nowhere else** — a history
entry's ⌘K stays the actions it always was, since converting a colour is not something you reach
for while browsing what you copied. **There is no submenu** either, the palette's menu being one
level deep, so each row states its value through `PopoverMenuItem.detail`, never `shortcut`, which
renders one keycap per character. The rows carry `PopoverMenuIcon.blank`, a run of rows under one
repeated eyedropper saying nothing, and the menu keeps the standard `menuWidth`: every notation
fits it, and a menu that widened for its content would jump as rows changed.

`ColorSwatch` is the one place a colour is drawn — row thumbnail, preview and card alike — over a
checkerboard built only when there is alpha to show, so an opaque colour never pays for a `Canvas`
nothing can see. The preview shows the colour and the copied text and nothing else. Detection is
narrow by design: anything past 64 UTF-8 bytes is not a colour, and no named colour (`red`) is
recognised, since a bare English word is prose far more often than CSS — and **a colour is never
named**: `#D6D6D6` is a swatch and its digits, never *Silver*. `NSColorList` naming was built,
measured and removed; it knew only the 59 names macOS ships, so most colours read as nothing, and
CSS's own (`gainsboro`) are in no catalog at all. The card runs **after** the calculator, which
costs nothing — no colour notation is also an expression.

`ColorCard` is built from the calculator card's own parts — `LeadCardColumn` and
`.leadCard(selected:)` — so a lead card can't change height or hover with its kind. Its swatch is
**stretched to the value column rather than sized**, since no notation has a fixed height.

## Pinned entries

A row's ⌘K Actions menu carries **Pin Entry / Unpin Entry** (⌘., since ⌘P opens the type filter),
persisted as a `pinned_at` column on `items` —
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

The ten palette slots shared with launcher favorites address this visible Pinned block too. A slot
uses the current query and type filter, so its first entry is the first visible pin; a missing slot is
a no-op. They are fixed to the physical number row, with ⌘1…⌘9 then ⌘0 as their labels.

`load` reads every pinned row plus the newest 1000 unpinned ones as two indexed branches over a
partial index on `pinned_at` (`Tests/clipboard-test.swift` covers the shape). The single
`pinned_at IS NOT NULL OR rowid >= ?` form reads better but cannot be driven from an index while
holding row order, so it scans the whole table — ~12ms against ~1ms at 200k rows, on the main actor
at launch.

## Referenced files

A file copied in Finder is recorded as a reference, never as a copy: Tinycast writes nothing to
disk for it, and the row's path points at the original wherever it lies. That is the whole reason
`imagePath` stays nil for a `.file` row — `owns()` is the one ownership rule, and a path it never
sees can never be deleted by `deleteBlob` or a retention cut. `clipboard-test`'s
`referencedFilesOutliveTheirRows` is the case that pins it, across `remove`, a retention cut and
Clear History alike.

**Pasting writes two flavours.** `public.file-url` so Finder, Mail and anything file-taking receive
the *file*, and `.string` carrying the **path** — deliberately not Finder's own choice of the name,
because a text field or Terminal almost always wants a path, a name is recoverable from a path and
a path is not recoverable from a name. "A name arrived where a file was meant" is the bug being
fixed, so it must not be reintroduced on the way out.

**A vanished file is reported, never silently swallowed and never auto-deleted.** `Paster.write`
returns false, the coordinator raises a HUD, and the row survives — history is a record of what
happened, and the recorded path is still the answer to "where was it?". The preview says so in
place, and the Path row keeps showing where the file used to be.

`FilePreviewThumbnailer` is the row tile and the preview still. `QLThumbnailGenerator` is the only
thing that renders a *content* thumbnail for any type — a video's poster frame, a PDF's first page
— and with `representationTypes: .all` it falls back to the type icon itself, so every file paints
something through one path. It copies `ImageThumbnail`'s shape exactly: two byte-bounded caches
split at 128px, cost measured as the real bitmap footprint, and `purgePreviews()` called from
`PaletteWindowController.hide()` beside the other two.

**The player's teardown is the part with a lifetime to get wrong.** `orderOut` leaves the SwiftUI
tree mounted, so `onDisappear` never fires on hide — which is exactly why `hide()` already has to
purge caches by hand. `PaletteState.isVisible` is therefore the second half of the player's
`.task(id:)` key, alongside the URL, so one mechanism covers both teardown triggers with no
`onChange` racing it. Teardown calls `replaceCurrentItem(with: nil)` and not merely `pause()`: a
paused `AVPlayer` still holds its asset reader and decoder open, which is how a 100 MB budget goes.
Nothing ever autoplays — arrow-keying a list of twenty videos must not start twenty decodes.

**A backup carries the path, never the bytes.** `BackupClipboardItem.file` exports `text` and no
blob, a file already gone at export time is counted missing, and a restore drops a row whose path
does not exist on this Mac — the same thing the Raycast import already does for an image path.
Carrying file bytes would make a backup unbounded and defeat the point of referencing in place.
