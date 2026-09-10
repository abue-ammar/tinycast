# Clipboard history

## Invariants

- **`clipboardEnabled` ships on — the only feature switch that does.** Absence of the key therefore
  has to outrank a stored `false` in `AppSettings.init`, and off means fully off: the poller stops,
  the SQLite file closes, the launcher command and its shortcut go, and Tab skips the screen.
  `ClipboardCoordinator.applyEnabled()` is the single place that applies it.
- **↵ and ⌘↵ are one swapped pair, and `ClipboardCoordinator.activate(_:inverted:)` is the only
  place that reads which way round they sit.** `clipboardDefaultAction` names what ↵ does — paste
  (the default) or copy — and ⌘↵ always does the other. ⌘1…⌘0 on a pin and a double-click go
  through the same call, so no surface can drift from the setting; ⌥↵ pastes regardless, since
  keeping the window open is a paste-only idea. The ⌘K menu puts the default first with the ↵ chip.
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
- **Recognized text is search metadata and nothing else.** It lives in its own `item_text` table,
  never on `ClipboardItem` and never in the resident window, so no surface can paste it, copy it,
  or classify an entry by it. What an entry *is* still comes from the content that was captured.
- **No recognition ever runs in the app process.** `ClipboardTextWorker` spawns one bundled
  `ClipboardTextHelper` per item and reaps it, which is the whole reason Vision's and PDFKit's
  allocations do not accumulate in Tinycast. The helper is handed a path and answers with text.

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
as a genuine copy. `PasteboardFiles` reads each item's own `public.file-url`, so a copied `http` URL stays a link;
returns nil rather than an empty array, so the text branch runs; caps a batch at
`maxCapturedFiles`, so a Finder select-all cannot insert ten thousand rows on one tick; and
**rejects a file under a volatile root** (`/tmp`, `/var/folders`, `~/Library/Caches`), because an
app that stages a temp export beside better inline content must keep the inline content. Paths come
back reversed so the *first* file copied ends up leading the history. Durability checks stop after
32 accepted files, and decoding stops with them: the reader takes the cap and the durability test
together rather than filtering a list it has already decoded whole. Rejected paths do not consume
the cap, and even a rejected modern file URL suppresses the legacy filenames fallback. The uncapped
`PasteboardFiles.urls(on:)` that attachments use is the same reader with no limit and no test.

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
inserts, original-text search, and pruning stay on the main actor.
Image copy uses Foundation’s `mappedIfSafe` hint before publishing the original PNG and marker.

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
The FTS query picks its newest `searchLimit` row IDs before materializing rows, so a broad query
never builds more items than it can show. Pins are still matched separately in memory, and the type
filter applies after the limit. `promote` updates the row's timestamp and rowid in one statement
rather than deleting and re-inserting it, because a delete would take the row's recognized text with
it; an update trigger moves the original-text FTS entry to the new rowid. The UUID and the image blob
are untouched.

Files under the store's own `imagesDir` are **owned**: pruned and deleted with their row. External
references — an image imported from another app's cache — are left on disk when the row goes. A
retention cut can strand hundreds of files, so those deletions run off the main actor to keep
capture-time pruning from hitching.

## Image and PDF text search

**Search text in images and PDFs is off by default.** The per-machine switch is excluded from
settings backups. A cold disabled launch creates no OCR schema, indexer, search task or Vision request,
and loads no extracted strings. Existing derived data stays on disk when disabled and is reused on
reenabling; deletion and retention still remove it with its original item.

When both clipboard history and text search are enabled, `AppCore` creates its
`ClipboardTextIndexer`. It recognizes locally with Vision's `RecognizeTextRequest`, starting one
background-priority job after two seconds without input, even while the palette is open. A 250 ms
pause separates items; continued typing or mouse movement defers the next job. Existing and imported
history is backfilled, including rows beyond the resident window. Nothing recognizes on the capture
or search path. When only failed work is left the indexer sleeps until a retry is due — a new capture
wakes that wait — and an empty queue exits rather than polling.

Turning either switch off cancels the run in flight; the indexer is kept and reschedules itself once
that run winds down, which is why `applyClipboardTextSearch` can be called again at any time.

Recognition runs in a bundled `ClipboardTextHelper`, one item at a time, and Vision's and PDFKit's
state leaves with it. The parent accepts at most 32 KB from the helper's output pipe, propagates
cancellation, and terminates and reaps a helper that runs past 60 seconds. `ClipboardTextWorker`
does its blocking read and wait on its own `DispatchQueue`, never the cooperative pool. No helper
exists while text search is off or the queue is empty.

Images include owned clipboard PNGs and referenced image files. Referenced PDFs use PDFKit's embedded
text page by page, with Vision OCR for pages without text. Mixed text-and-scan documents therefore
remain searchable; images embedded on a page that already has text are not separately OCR'd. All
processing stays on this Mac. Extracted text is search metadata, never the value pasted or copied.

The derived `item_text` table and its trigram FTS index persist metadata without adding extracted
strings to `ClipboardItem` or loading them into the resident history. Original text/path search returns
immediately. A cancellable off-main SQLite query adds OCR-only matches for All, Images and Files;
Text, Links, Emails and Colors never consult OCR. Type classification always uses original content.
There is no spinner or skeleton. Pins lead in pin order, ordinary unpinned matches keep theirs, and
OCR-only unpinned matches of the active type fill what is left of the same `searchLimit` budget, in
history recency rather than extraction order — a deliberate choice to let an ordinary match answer
first. Queries under three characters consult only the resident window and pins.

Each reader takes a 2 MiB SQLite cache budget and closes its connection when it finishes. A new
query or filter, palette dismissal, disabling, and any history mutation cancel work that is now
obsolete, and a request identity keeps a late answer from publishing. Publication follows the
selected item by UUID; pinning and promoting keep the matches already on screen while it refreshes.
Clearing or reloading rotates the extraction generation, and the insert selects its row rather than
naming it, so it cannot recreate a deleted entry. Backups stream the original fields and never load
OCR metadata.

Work is bounded: files up to 32 MB, the first 64 PDF pages, a 4,194,304-pixel bitmap budget with a
4096-pixel maximum edge, and 32 KB of UTF-8 text per item. An empty, unsupported or oversized input
is a completed attempt. Failed recognition, a locked or unreadable input and a helper failure go to
`item_text_failures` instead: up to three attempts 30 seconds apart, which never block another item.
Success and deletion clear that state. Enabling text search resets failures and earlier empty
attempts so they can be tried again, keeping recognized text that is not empty — so an empty input
may be reprocessed on a later launch, but nothing retries forever inside one session. Long bitmaps
are recognized in overlapping 2048-pixel tiles, with Vision's relative minimum text-height cutoff
disabled so it cannot discard small text on a tall screenshot or page. A referenced file is read once
when it is indexed; editing it later does not refresh the historical search text. Backups carry the
original content and references, and a restored entry is recognized again.

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
  it. Original text on pinned rows is matched **in memory**
  rather than taken from the FTS result, since the statement's `LIMIT` could otherwise drop one out
  of a busy query's matches — which holds because every pinned row is resident in `items`, however
  old (`load` fetches them all, and neither the window trim nor pruning drops one). OCR metadata
  for matching pins is queried separately off-main without the unpinned result limit.
- **Unpinning re-recencies.** An unpinned row rejoins the history as its _newest_ entry (Raycast does
  the same) rather than dropping back into the date bucket it came from, which would scroll the list
  out from under the selection. It uses the same atomic timestamp and rowid update as `promote`.
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
