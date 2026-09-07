# Quicklinks

A quicklink turns a URL, search, file, folder or deeplink into a first-class command: searchable in
the launcher, bindable to a global shortcut, and openable in a chosen app. Dynamic placeholders let
one quicklink adapt to typed input, the clipboard, the selection, or the date.

The feature ships **off**. **Settings → Quicklinks** carries the switch and its launcher-visibility
companion. Off is fully off: no launcher section, no `Create` / `Search` / `Import` / `Export`
Quicklinks commands, and `QuicklinkCoordinator.openQuicklink` — the single funnel palette activation and global
shortcuts both reach — refuses to open anything. Bindings stay registered, so re-enabling restores
every shortcut without re-registering.

## Invariants

- **Quicklinks are authored data, and their store never deletes.** A database that will not open is
  **reported, never discarded** — `ClipboardStore`'s delete-and-recreate is only sound because history is
  regenerable, and a link library is not. The database lives in **Application Support**, not Caches.
- **`Model/` stays Foundation-only (plus SQLite3) and pure** for `quicklink-test` — the home directory is
  injected, never read. `Service/QuicklinkLauncher` owns every `NSWorkspace` call.
- **Drawing an argument field reads nothing.** The header's chips come from
  `SnippetTemplateEngine.declaredArguments(in:)`, a parse of the template alone, so moving the
  selection never touches the clipboard or the frontmost app's selection. Only opening does.
- **`Quicklink.precedes` is the one display order**, sorted through by both the store and the `AppIndex`
  slice.
- **A disabled quicklink is inert, not gone.** `isEnabled == false` takes it out of root search and out
  of Search Quicklinks, and `openQuicklink` refuses it, so no surface can offer or open it. Everything
  attached — name, link, alias, shortcut, favorite slot, ranking — stays exactly as it was. The
  **Settings → Quicklinks** row is the one place that turns it back on, through the checkbox launcher
  items and custom commands carry: last in the row, dimming the alias field and shortcut recorder.
- **There is one template engine.** Quicklinks expand through `SnippetTemplateEngine` rather than a
  second parser, which is what makes `| raw` mean something — it opts a value out of the automatic
  percent-encoding a URL destination asks for. `{selectedText}` is accepted as an alias for
  `{selection}`, but nothing ever *writes* it.

## Destinations

`QuicklinkDestination.detect` decides what a link is from its shape alone — no filesystem or Launch
Services read — which is what keeps it pure and covered by `Tests/quicklink-test.swift`. In order:

| Shape                                                  | Result                                                            |
| ------------------------------------------------------ | ----------------------------------------------------------------- |
| `~/…`, `/…`, `file://…`                                | `.path`, tilde expanded against the injected home                 |
| `http:` · `https:`                                     | `.web`                                                            |
| `smb:` · `afp:` · `nfs:` · `ftp:` · `sftp:` · `ftps:`  | `.network`                                                        |
| any other `scheme:`                                    | `.deeplink` (`spotify://`, `slack://`, `shortcuts://`, `mailto:`) |
| a bare host with a letter-led TLD (`github.com/a?b=c`) | `.web`, `https://` prepended                                      |
| anything else                                          | nothing — the link is rejected                                    |

Two false positives are excluded deliberately, because both are commoner than the schemes they would
shadow: a one-letter "scheme" is a Windows drive letter, and a `scheme:` whose remainder is all
digits is a `host:port`. A literal space is rescued by encoding it; anything else illegal is a real
error, since blanket re-encoding would corrupt the `%xx` the template engine already produced.

The detected kind decides the icon a row draws when the quicklink has no icon of its own, and
`usesURLEncoding` decides whether substituted values are percent-encoded. That question is answered
from the link's **prefix**, not from a parsed destination, because the encoding has to be chosen
before the placeholders are resolved.

## Placeholders

Quicklinks reuse Tinycast's one template engine — the same
[`SnippetTemplateEngine`](snippets.md#template-tokens) snippets use, so every token and every modifier
is available and there is no second parser to keep in sync. `{cursor}` and `{snippet:…}` are text
concerns with nothing to resolve against in a destination, so they are left literal.

```text
https://google.com/search?q={argument}
https://github.com/search?q={argument name="Repository"}
https://translate.google.com/?text={selection}
https://chat.openai.com/?q={clipboard}
~/Notes/{date format="yyyy-MM-dd"}.md
```

**Values going into a URL or deeplink are percent-encoded automatically**, so a search term with a
space or an `&` can't truncate the destination. Encoding is applied _after_ the modifier pipeline, so
`| uppercase` can't rewrite the `%xx` hex, and it is skipped when the template already spoke for
itself — `| raw` opts out, `| percent-encode` has done it once already. A local path is never
encoded: `%20` in a path is a literal, not a space.

`| raw` opts out of more than the escaping. Whether a link is a website, a path or a deeplink is
decided by `QuicklinkDestination.detect` on the **expanded** text, so an unencoded substituted value
that begins with a scheme picks the destination kind — a `{clipboard | raw}` holding `file:///…`
resolves to a local path rather than to the web link the template looked like. Encoding is what
normally prevents that, which is why `| raw` is a deliberate authoring choice and not a default.

`{selectedText}` is accepted as an alias for `{selection}`, so a link pasted from Raycast's docs
works unchanged. `{selection}` stays the canonical spelling and is the only one the editor's
**Insert…** menu writes. `{query}` is accepted as an alias for `{argument}` for the same reason;
a Raycast import rewrites it to `{argument}` before the row is stored.

## Arguments

A quicklink whose placeholders still need values doesn't open — it collects them **in the header,
beside the search field**, as inline chips. There is no argument screen: the row that owns the values
stays selected and visible the whole time, the way Raycast does it. The mechanics of the strip belong
to the palette and are described in
[palette.md](palette.md#inline-row-arguments); what quicklinks own is which fields appear and what an
answer means.

`promptedArguments(for:)` is the one place that decides: the `{argument}`s the link declares, read
straight off the template by `SnippetTemplateEngine.declaredArguments(in:)` — a pure parse, so nothing
is expanded and no clipboard is read to draw a chip — plus the synthetic **"Selected Text"** field when
the setting says ask. An argument with a `default=` answers itself and is never asked for.
`QuicklinkArgumentsAccessory` turns that list into the strip; a field declaring `options=` is chosen
from the palette's own menu rather than typed. The strip is placed `.afterQuery` in root search — a
glyph, then the chips, right after the typed text — and `.besideSearchField` on Search Quicklinks,
where the field stays a filter with its prompt intact and the row below already carries the glyph.

**"Selected Text" is asked for up front, not after a failed read.** A chip cannot capture a selection,
so the field appears whenever the link reads `{selection}` and the setting is `.ask`. Left empty it
changes nothing — a selection the frontmost app *does* expose is still used — and only a typed value
replaces it. That is the one behavioural difference from the two-screen form it replaced, and it is
what lets the strip be drawn without capturing anything.

`openQuicklink(id:forcingDefaultApp:values:)` is the single funnel, and it captures the expansion
context on **every** call rather than holding one across a session, so `{clipboard}`, `{selection}` and
`{date}` are read at the moment the link opens. Reached from a global shortcut with the palette closed
too: the frontmost app is recorded first, the way `runSystemAction` does, so the selection comes from
the window the user was actually in.

↵ with the chips filled opens straight away, wherever the row was reached from — root search carries
its values through `LauncherScreen.argumentValues(for:)` into the same funnel, so a filled row never
takes a detour. **Only a shortcut whose values are still missing lands on Search Quicklinks**, on that
row, with its first empty chip focused — carried across by `PaletteState.pendingArgumentEntryID` and
`commandArguments`, both set after the show because `prepare` clears them. One argument surface, whether
the row is reached from root search, from Search Quicklinks or from a hotkey. A ⌘↵ "open with default
app" override survives that trip on `pendingDefaultAppOverride`, keyed by the quicklink it applies to.

**A launcher fallback fills the first argument.** Declaring a placeholder is exactly what puts a
quicklink in the `Use “…” with…` section (see [launcher.md](launcher.md#fallbacks));
`openQuicklink(id:filling:)` assigns the query to the first declared argument and opens at once when
that was the only one owed. It is never the "Selected Text" field: that one is not an `{argument}` and
is resolved by replacing the context, so seeding it there would expand to nothing.

When a template reads the selection and the app in front exposes nothing readable, **Settings →
Quicklinks** decides what happens: substitute the clipboard, or ask for it through the chip above.

## Opening

`QuicklinkLauncher` owns every platform effect. A path destination is checked with `fileExists`
first, so a deleted folder names itself instead of failing as a silent no-op. `Open With` resolves a
stored bundle ID through Launch Services; an app that has since been uninstalled reports a failure
with an **Open with Default** recovery button rather than silently falling back.

"Open in a new window" passes `--new-window` to the handler. Chromium and Firefox accept it, Safari
ignores it, and an app that doesn't understand an argument drops it — so the setting is honest about
applying only to handlers that accept one. Off is plain `NSWorkspace.open`, which reuses the
frontmost tab; that is what "prefer existing tabs" means, so it is the same switch rather than a
second one.

Every failure — unresolvable link, missing file, missing app, refused open — reports through
Tinycast's own dialog and leaves no partial state.

## Search and pinning

Quicklinks are their own `AppEntry.Kind`, their own `AppIndex` slice and their own launcher section,
between System Settings and Snippets. Only the **name** is indexed; the destination is not searchable
(a URL is a subsequence of almost any query) — beside the name, a quicklink answers to whatever
[user alias](launcher.md#user-aliases) its Settings row carries, which is why a hidden one dims the
field. Per-quicklink "Show in root search" filters the slice;
the pane's "Show in launcher" takes the section and the four Quicklink commands out of the
launcher together, leaving shortcuts and the pane itself working.

Three levers, narrowing in that order: the pane's switches take the whole feature out, the row's
**Enabled** checkbox makes one quicklink inert, and **Show in root search** keeps a quicklink openable
from Search Quicklinks and its shortcut while dropping it from the root list.

`Quicklink.precedes` is the one display order — pinned first in the order they were pinned, then the
rest by name — and both the store and the launcher slice sort through it, so the two can never
disagree. **Pinned means the top of the Quicklinks section**, not above Applications: a second
position in root search would need a second `AppEntry.Kind`, which the kind invariant forbids for one
feature. The Search Quicklinks screen gives pins their own section, like the clipboard's.

## Search Quicklinks

`PaletteMode.quicklinks` is a sub-screen reached from the `Search Quicklinks` command. It is shaped
like Search Snippets and the clipboard: the list on the left, a **detail pane** on the right showing
the selected quicklink's glyph over an Information block (name, link, the app it opens with, its
shortcut, when it was created). Like Calculator History it stays out of the Tab cycle and exits via the
back chevron or a bare backspace.
Its ⌘K menu carries Open (`↵`), Open With Default App (`⌘↵`, only when a handler is saved), Edit,
Duplicate, Pin/Unpin (`⌘.`), Hide/Show in Root Search, Show in Finder (`⌘F`, only for a resolved
path), and Delete (`⌘⌫`).

Choosing an _arbitrary_ app belongs to the editor, which has a picker; `PopoverMenu` is a flat list
with no nesting, so the palette offers the one alternative that always exists — bypass the saved app
and use the system handler, once, without changing what is saved.

## Storage

```text
~/Library/Application Support/<bundle-id>/quicklinks.sqlite3
```

Quicklinks are **authored data**, which decides the one way `QuicklinkStore` differs from
`ClipboardStore` — they are neighbours in Application Support, and otherwise mirror each other (WAL,
prepared statements, an `isolated deinit`):

- **A database that won't open is never deleted.** `ClipboardStore` discards and recreates a corrupt
  file because a history is captured rather than authored; doing that here would destroy the user's
  library. The store publishes `isAvailable == false`, every mutation refuses with
  `QuicklinkError.storageUnavailable`, and the pane says so. `Tests/quicklink-test.swift` asserts the
  file survives byte-for-byte.

`CREATE TABLE IF NOT EXISTS` leaves an existing table alone, so a new column arrives as an unchecked
`ALTER TABLE … ADD COLUMN … DEFAULT` right after the schema, which fails harmlessly once the column is
there. That appends it physically, so the prepared statements **name their columns in the struct's
order** rather than the table's, and the row reader stays a straight top-to-bottom read.

Editing preserves the UUID, and with it the quicklink's shortcut, favorite slot, visibility and
learned ranking. Deleting goes through `AppCore`, which unwinds all four before removing the row.
Duplicating takes a **new** identity, so the copy can't inherit the original's shortcut.

## Hotkeys

`HotKeyAction.quicklink(id:)` persists under `hotkey.quicklink.<uuid>` with a
`boundQuicklinkIDs` index, the same shape custom commands use — both are per-item rather than
per-catalog-entry, so both need an index for `start()` to re-register from. The store therefore loads
**even while the feature is off** and before `hotKeys.start`: the stale-binding prune reads that
list, and an unloaded store would look like "every quicklink was deleted" and throw the shortcuts
away.

## Import & export

`QuicklinkArchive` is a versioned JSON document (`{"version": 1, "quicklinks": [...]}`), pretty-printed
with ISO 8601 dates so it can be hand-edited; a bare array decodes too, and only `name` and `link` are
required. Duplicate detection is by **name or destination** — either match means the user already has
it — compared against the existing library _and_ against the rest of the incoming file, so one file
can't import its own duplicates. Skipped entries are counted and reported in the summary. An import
takes a fresh identity for every entry, so it can never collide with a shortcut an existing quicklink
owns.

Quicklinks and their bindings also ride in native settings backups, and the settings flags with them.
Unlike `snippetsEnabled`, `quicklinksEnabled` grants no permission class and enables no listening, so
excluding it would be cargo-culting.

The encrypted `.rayconfig` flow in **Settings → Backup** can import Raycast's quicklinks as an
independently selectable category. Tinycast reads `name`, `link`, `createdAt` and the optional
`openWith` / `applicationId` from the export's `quicklinks.quicklinks` collection, resolving an app
path through `openWithPlatforms` when the field is a platform id. Invalid entries are skipped; valid
entries merge into the existing library the same way **Import Quicklinks** does. Importing at least
one turns the feature on — the switch grants no permission class.

## Standalone harness

```sh
./Scripts/run-tests.sh quicklink-test
```
