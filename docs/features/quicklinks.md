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
  injected, never read. `Service/QuicklinkLauncher` owns every `NSWorkspace` call and
  `Service/QuicklinkArgumentSession` the prompt state.
- **`Quicklink.precedes` is the one display order**, sorted through by both the store and the `AppIndex`
  slice.
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
**Insert…** menu writes.

## The argument prompt

A quicklink whose placeholders still need values doesn't open — it collects them first, in the
palette, as `PaletteMode.quicklinkArguments`.

Arguments are collected **one at a time** because the palette has exactly one text field, and that
field _is_ the current argument's input. The screen above it lists every argument with its answer so
far. ↵ commits and advances; on the last one it opens. Backspace on an empty field steps back to the
previous argument and restores what was typed there, so a typo in the second of three fields costs
one keypress rather than the whole flow. An argument declaring `options=` renders its choices as
ordinary selectable rows, so the flat selection index behaves exactly as it does in every other list.

`QuicklinkArgumentSession` captures the expansion context **once**, before the first prompt — the
same rule snippet expansion follows — so `{clipboard}`, `{selection}` and `{date}` cannot drift while
the form is open. Reached from a global shortcut with the palette closed too: `AppCore` records the
frontmost app first, the way `runSystemAction` does, so the selection is read from the window the
user was actually in.

When a template reads the selection and the app in front exposes nothing readable, **Settings →
Quicklinks** decides what happens: substitute the clipboard, or ask for it through the same prompt as
any other argument (a synthetic "Selected Text" argument).

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
(a URL is a subsequence of almost any query). Per-quicklink "Show in root search" filters the slice;
the pane's "Show in launcher" hides the whole section.

`Quicklink.precedes` is the one display order — pinned first in the order they were pinned, then the
rest by name — and both the store and the launcher slice sort through it, so the two can never
disagree. **Pinned means the top of the Quicklinks section**, not above Applications: a second
position in root search would need a second `AppEntry.Kind`, which the kind invariant forbids for one
feature. The Search Quicklinks screen gives pins their own section, like the clipboard's.

## Search Quicklinks

`PaletteMode.quicklinks` is a sub-screen reached from the `Search Quicklinks` command. Like
Calculator History it stays out of the Tab cycle and exits via the back chevron or a bare backspace.
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

Application Support, not Caches: quicklinks are **authored data, not a regenerable cache**. That one
fact decides the two ways `QuicklinkStore` differs from `ClipboardStore`, which it otherwise mirrors
(WAL, `PRAGMA table_info` column sniffing plus `ALTER TABLE` for migrations, prepared statements, an
`isolated deinit`):

- The database lives beside the snippets library rather than in the cache.
- **A database that won't open is never deleted.** `ClipboardStore` discards and recreates a corrupt
  file because history is regenerable; doing that here would destroy the user's library. The store
  publishes `isAvailable == false`, every mutation refuses with `QuicklinkError.storageUnavailable`,
  and the pane says so. `Tests/quicklink-test.swift` asserts the file survives byte-for-byte.

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

## Standalone harness

```sh
./Scripts/run-tests.sh quicklink-test
```
