# Alfred import

Tinycast reads an `Alfred.alfredpreferences` package: the folder Alfred keeps its whole
configuration in, reachable at **Alfred → Preferences → Advanced → Reveal in Finder** and named
`Alfred.alfredpreferences` either inside `~/Library/Application Support/Alfred/` or inside the sync
folder Alfred was pointed at. Nothing is decrypted and no keychain is read — the files are plain
`prefs.plist`s, JSON and scripts.

## Invariants

- **The newest `preferences/local/<id>` profile wins.** Alfred keeps a Mac's own settings under
  `preferences/local/<id>`, one folder per machine a package has been synced through, and writes the
  current Mac's folder last. The reader overlays that one profile onto the global `preferences/`,
  which is what Alfred itself resolves to. Two profiles written in the same second resolve by folder
  name, so a flattened copy of a package still imports deterministically.
- **A category is dropped, not half-applied.** `Result.selecting(_:)` empties what was not ticked,
  and every applier is per-field, so an unticked box cannot leave a setting behind. A workflow's
  chord belongs to **Shortcuts** rather than to **Workflows** and goes with that box.
- **A workflow's chord is read back off the store.** `CustomCommandStore.add(contentsOf:)` returns
  the drafts that landed, so a command whose name collided is not left with an unbound chord.
- **Never commit a real package as a fixture.** `alfred-import-test` builds its own.
- **Snippets are rewritten into our template syntax, and the harness proves it.** Alfred writes
  `{date:yyyy-MM-dd}`, the engine reads `format=`, so the mapping is only trustworthy if the real
  `SnippetTemplateEngine` expands the result — which is why the harness compiles both.

## Package layout

| Path | Holds |
| --- | --- |
| `preferences/<feature>/prefs.plist` | the synced settings |
| `preferences/local/<id>/…` | one Mac's own overrides |
| `snippets/<Collection>/<name> [<uid>].json` | one snippet per file, plus the collection's `info.plist` |
| `remote/pages/pages.data`, `<uid>.data` | the web-bookmark pages and their items |
| `preferences/features/websearch/prefs.plist` | `customSites`, the searches you added |
| `preferences/features/websearch/<site>/prefs.plist` | one keyword per built-in search |
| `workflows/user.workflow.<uid>/info.plist` | one workflow's graph |

**Clipboard history is not in the package.** Alfred keeps it in
`~/Library/Application Support/Alfred/Clipboard History/`, so there is nothing to import and the
category does not exist here. Neither does Alfred have window management, a favourites list, or a
"paste as plain text" preference — those are stored nowhere in the package.

## Mapping

| Category | Alfred | Tinycast |
| --- | --- | --- |
| Shortcuts | `hotkey/prefs.plist` → `default`, `features/clipboard/prefs.plist` → `hotkey` | the palette chord and `CommandID.clipboardHistory` |
| Search scope | `features/defaultresults/prefs.plist` → `scope` | `searchScopes`, abbreviated and deduped |
| Snippets | `snippets/**/*.json` | snippets, with the collection's keyword affixes applied |
| Bookmarks & searches | `remote/pages/*.data`, `customSites`, `features/websearch/<site>/` | quicklinks |
| Workflows | `workflows/*/info.plist` | custom commands |

**A chord** is a Carbon key code plus a raw `CGEventFlags` value, whose bits sit eight above the
Carbon ones; `key: -1` is Alfred's "unset". A bare key needs a commanding modifier here exactly as it
does everywhere else, bar the function keys. `string` is a layout-dependent glyph and is never read.

**A search keyword becomes the quicklink's keyword.** The launcher invokes `keyword query`
directly, so `AlfredImport.named(_:keyword:)` is no longer needed for searches — only custom
commands still carry the keyword in parentheses, having no keyword field of their own.

**Snippets** are one file per snippet, and a collection's `info.plist` carries the keyword prefix and
suffix wrapped around every keyword typed into it — both are read from there, since
`preferences/workflows/trigger/snippet` is Alfred's *workflow* snippet trigger and not a collection.
Alfred's placeholders are translated: `{date:FORMAT}` and
`{date -7d:FORMAT}` become `format=` and `offset=`, `{clipboard:2}` becomes `offset=`, an
`{clipboard:uppercase}` becomes a modifier, and the four named date styles become the system patterns
they stand for. `{query}` and `{selectedText}` need nothing — the engine already accepts both.

**Bookmarks** are the `remote.alfred.openurl` items of every page. Alfred's own pages open files, run
system commands and drive iTunes, and none of that is a link, so `remote.alfred.launchfile` and the
rest are skipped rather than half-mapped. A bookmark with an empty label is named after its host.

**Searches** come in two shapes. `customSites` carries its own URL and needs nothing from us. Alfred's
built-in searches store only a keyword — the URL template lives inside Alfred — so
`AlfredQuicklinkImport.defaultSearches` holds the templates, keyed by the folder name Alfred's
preferences use. **A folder missing from that table is reported by name, not guessed at**: its keyword
is reported in the import summary so a missing template is visible rather than silently dropped.
`{query}` is rewritten to `{argument}` by `Quicklink.replacingArgumentTokens`, shared with the Raycast
import.

**Workflows** are a graph and a custom command is one script, so a workflow comes over only when it
*is* that shape: not disabled, exactly one keyword or hotkey trigger, and that trigger reaching
exactly one Run Script node whose language is Alfred's own bash with the script inline rather than in
a file. Everything else is counted in the import summary. `{query}` becomes `"${1}"` and the command
declares the argument; an occurrence inside quotes is skipped rather than rewritten into something
that would run differently. A workflow's hotkey becomes the command's chord. Alfred counts a keyword's
and a hotkey's argument setting differently, so each is read in its own vocabulary: a keyword's `2` is
"No argument" while a hotkey's `0` is, and a hotkey's `3` is a fixed argument the workflow supplies
rather than anything the user types.

Imported commands are **merged** into the library, never replacing it, and the import asks first
through the same confirmation a backup carrying executable commands gets.

## Layout

`AlfredPreferencesReader` walks the package and returns `AlfredImport.Result`, which holds only
already-mapped domain values — so `alfred-import-test` compiles it with the real
`SnippetTemplateEngine`, `Quicklink`, `CustomCommand` and `KeyShortcut` and no app at all. Each
feature owns its own mapping, as it does for Raycast: `AlfredSnippetImport`,
`AlfredQuicklinkImport`, `AlfredWorkflowImport` and `AlfredHotkeyImport`.

`BackupActions.importAlfred` runs the reader off the main actor, then writes snippets, quicklinks and
commands the way the Raycast import does, and composes a `SettingsBackup` for the two settings it
carries.
