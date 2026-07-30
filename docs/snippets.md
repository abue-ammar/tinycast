# Snippets

Snippets are reusable plain-text templates stored as Markdown. They can be expanded from launcher
results, or automatically when an enabled keyword is typed in another app.

## Storage, identity, and migration

Each app channel owns a separate library:

```text
~/Library/Application Support/<bundle-id>/Snippets/
```

Debug (`com.tinycast.app.dev`), beta, and stable therefore never share snippet files. The storage
root and bundle identifier are injectable in the standalone harness so tests cannot touch a real
library.

A stored snippet's identity is the standardized path of its Markdown file. Changing `name` or other
frontmatter keeps the same identity. Renaming a file outside Tinycast appears as deletion of the old
record plus creation of a new one. Saving always updates the existing path; creating snippets with
the same name uses distinct filename suffixes.

The first successful load initializes the channel once, in this order:

1. Copy Markdown files from `~/.config/tinycast/snippets/` when any exist.
2. Otherwise import the channel's legacy `snippets.json`.
3. Otherwise install the starter snippets.

Migration uses a staging directory and leaves legacy sources untouched. Its completion marker lives
beside `Snippets/`, not inside it, so deleting every snippet creates a persistent empty library rather
than reinstalling samples. A failed JSON migration writes no marker and is retried on the next load.
Malformed Markdown is reported per file while valid files remain available.

## Importing from Raycast

The encrypted `.rayconfig` flow in **Settings → Backup** can import Raycast's built-in snippets as
an independently selectable category. Tinycast reads `name`, `text`, and the optional `keyword` from
the backup's `builtin_package_snippets.snippets` collection. Invalid entries are skipped; valid entries
are added in source order without overwriting the existing library. Duplicate names receive the same
filename suffixes as snippets created in Tinycast, and duplicate keywords are preserved.

Imported snippets are enabled and launcher-visible, while their insertion HUD remains off. Importing
never enables automatic keyword expansion or grants Input Monitoring or Accessibility consent.

## Markdown format

Frontmatter is optional. A file without an exact opening `---` line is treated entirely as the body,
with a display name derived from its filename.

Canonical output uses this order:

```markdown
---
name: "Meeting Notes"
keyword: "!notes"
category: "Work"
enabled: true
show_in_launcher: true
show_hud: false
---
Template body
```

`name` is optional when reading and defaults from the filename. `keyword` and `category` are
optional. `enabled` and `show_in_launcher` default to `true`; `show_hud` defaults to `false`.
The legacy JSON migration also defaults a missing `showHUD` field to `false`.

String values must use double quotes. The codec escapes and decodes `\\`, `\"`, `\n`, `\r`, and
`\t`; unsupported escapes, unquoted strings, duplicate or unknown keys, non-exact delimiters, and
booleans other than lowercase `true` or `false` are rejected. The legacy keys `showInLauncher` and
`launcher` are accepted on read, but saves always emit `show_in_launcher`.

Everything after the closing delimiter's line terminator is the body. Leading and trailing blank
lines, CR/LF choices, Unicode, and later lines containing `---` are preserved exactly when parsing.

## Template tokens

The template engine is Foundation-only and receives one captured expansion context containing the
clipboard text, selected text, clock, calendar, locale, and time zone. If arguments require a prompt,
the same context is reused afterward, so clipboard, selection, date, and time cannot drift while the
prompt is open.

Supported tokens:

| Token | Result |
| --- | --- |
| `{clipboard}` | Captured plain-text clipboard value |
| `{selection}` | Captured selected text from the target app, when Accessibility can read it |
| `{date}` | Captured date in the current locale |
| `{time}` | Captured time in the current locale |
| `{date format="yyyy-MM-dd"}` | Captured date using the supplied `DateFormatter` format |
| `{argument}` | An argument named `Argument` |
| `{argument name="Recipient"}` | A named argument requested before expansion |
| `{snippet:Name}` | Another snippet resolved by name, then keyword |
| `{cursor}` | Final insertion point |

Arguments are unique and requested in first-appearance order, including arguments inside referenced
snippets. Inserted clipboard, selection, and argument values are literal: token-shaped text inside a
value is not expanded again.

Snippet references are case-insensitive. Duplicate names or keywords resolve deterministically by
file-path identity. Nested references support five levels, detect cycles by file identity, and leave
the original reference token visible when a target is missing, cyclic, or beyond the depth limit.

All cursor tokens are removed. The first cursor in the final expanded traversal wins, including one
inside a nested snippet, and its offset uses Swift `Character` boundaries so composed Unicode moves
the caret correctly.

## Launcher and automatic keywords

An enabled snippet with `show_in_launcher: true` appears in launcher search. Its name, category, and
keyword are searchable; only a keyword match receives the keyword ranking boost. Launcher expansion
may interactively request Accessibility because it begins from an explicit user action. Input
Monitoring is not needed for launcher expansion.

Automatic keyword expansion is disabled by default. Enabling it in **Settings → Snippets** first
shows an explanation, then stores consent and requests only missing Input Monitoring and
Accessibility grants. The consent flag is intentionally excluded from settings backups, so importing
a backup cannot enable keystroke listening.

Each permission is managed by the pane whose feature needs it, through one shared `PermissionCard`:
Input Monitoring in **Settings → Snippets**, Accessibility (which snippet delivery shares with
clipboard pasting) in **Settings → Clipboard**.

Runtime status is explicit:

- **Off** — consent is disabled and no keyword tap is retained.
- **Waiting** — consent is enabled, but a permission, active session, or live event tap is missing.
- **Active** — both grants are present and the listen-only event tap is running.

The listener never prompts from startup, a callback, or its health check. It preflights grants,
installs or repairs the tap when they become available, and tears it down after revocation, logout, or
disabling the setting. `stop()` is authoritative and clears the buffer. The buffer also resets on app
or session changes, Secure Event Input, navigation and modifier shortcuts, and 15 seconds of
inactivity. It is capped at 256 characters. Keywords are matched case-insensitively by longest suffix;
duplicates resolve by file identity. Tinycast-tagged synthetic events are ignored.

Immediately before deleting a matched keyword and before inserting its expansion, automatic delivery
re-checks consent, both permissions, Secure Event Input, the captured target app, and cancellation
generation. A failed gate leaves the typed keyword untouched.

## Insertion HUD

The insertion HUD is per snippet and off by default: the only gate is `show_hud: true`, set from the
snippet's editor in **Settings → Snippets**. There is no global preference and nothing HUD-related in
settings backups. Keyword-monitoring consent is separate and also excluded from backups.

After either launcher or keyword delivery is confirmed, Tinycast may show a brief non-activating,
click-through overlay with the snippet name. The AppCore-owned controller replaces and restarts a
visible HUD on repeated deliveries, follows the existing cursor-screen preference, and never prompts
for permissions or activates Tinycast. Failed, cancelled, rejected, or prompt-cancelled expansions do
not report completion and therefore cannot show it.

## Text delivery and pasteboard safety

The preferred path is one atomic Accessibility replacement. Tinycast requires a focused element with
readable text plus writable selected-range and selected-text attributes. For an automatic expansion it
also verifies that the exact captured keyword is immediately before the cursor before replacing it.
An Accessibility mismatch is rejected rather than guessed.

Some editors grant Accessibility but do not expose writable text attributes. In that case Tinycast
falls back to tagged keyboard events while keeping the same permission, consent, Secure Event Input,
target-app and cancellation gates. The fallback deletes the keyword first, waits for deletion to
settle, then inserts the expansion. Short single-line expansions of at most 100 characters use Unicode
keyboard events.

Longer or multiline fallback text uses a temporary paste only when the existing pasteboard's first
item has plain text that can be restored without another pasteboard write. Tinycast snapshots every
item, type and data payload, takes temporary ownership with the same item shape, and changes only the
first plain-text payload. Restoration mutates that owned item back in place; it never clears the
clipboard before a fallible restore. The pasteboard change count is checked before restoration, so a
newer copy is never overwritten. Empty, image-first, unreadable or otherwise unsafe pasteboards use
the Unicode-event fallback instead. The clipboard poller synchronizes to Tinycast's ownership changes
so temporary or restored text is not added as new history.

When Accessibility text state is readable, a long paste waits for evidence that the target changed.
If the editor cannot expose post-paste text state, a successfully posted paste is accepted only after
a conservative delay instead of being treated as a permanent failure. Cursor movement starts after
that confirmation or delay and after pasteboard restoration. Delivery completion is reported exactly
once only after the Accessibility replacement or event fallback (including requested cursor movement)
finishes successfully. Disabling automatic expansion or
terminating the app cancels pending delivery and deferred cursor movement; termination also completes
any pasteboard restoration still owned by Tinycast.

## External edits and conflicts

`SnippetsStore` publishes repository snapshots and per-file issues on the main actor while all file
I/O runs off-main. Its debounced watcher observes external edits and atomic replacements, discards
stale load generations, and rearms after the directory is renamed, replaced, or deleted.

Settings keeps an in-memory draft and writes only on **Save** or Command-S. **New** creates no file
until its first save. Saves and deletes include the loaded source revision. All repository instances
for one channel share a serialized owner, and each mutation uses `NSFileCoordinator` before
revalidating the path and source revision immediately beside the atomic write or removal. Cooperative
writers therefore produce a conflict instead of being overwritten. macOS path-based APIs cannot
provide a true compare-and-swap against an uncooperative process that writes in the final interval
between revalidation and mutation, so Tinycast does not claim that impossible guarantee.

Clean drafts adopt external changes. Dirty drafts offer Reload or Keep Editing, while externally
removed or renamed files offer Save as New or Discard and are never recreated implicitly.

## Standalone harness

Run the real model, codec, template engine, repository, keyword listener with a fake tap adapter, and
main-actor watcher against temporary roots:

```sh
swiftc -swift-version 6 Tinycast/Core/NotificationToken.swift \
  Tinycast/Core/Snippets/*.swift \
  Tools/snippets-test.swift -o /tmp/snippets-test && /tmp/snippets-test
```
