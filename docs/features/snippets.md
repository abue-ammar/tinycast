# Snippets

Snippets are reusable plain-text templates stored as Markdown. They can be expanded from launcher
results, from the dedicated browser below, or automatically when an enabled keyword is typed in
another app.

## Invariants

- **Snippets are channel-isolated and path-identified.** They persist under
  `~/Library/Application Support/<bundle-id>/Snippets/`; `StoredSnippet.ID` is the standardized source
  path, and an external rename is a delete plus a create.
- **The feature ships off, and its enable switch doubles as keyword-expansion consent.**
  `snippetsEnabled` is excluded from settings backups, and Accessibility — the only permission it needs,
  since the listen-only tap needs nothing more — may be requested **only** from that explicit Settings
  gesture, never from startup, callbacks, watchers or health checks.
- **All of `Model/` and `Service/` compiles into `snippets-test`** (it globs both), so the model, Markdown
  serializer, template engine, repository and keyword policies stay Foundation-only, and the AppKit files
  there keep their dependencies to what the harness can stub.
- The on-disk Markdown format is user-authored and user-editable — an interchange format, not an internal
  one.

## Storage and identity

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

The first load creates the folder and nothing else: a new channel starts with an empty library, and
snippets only ever arrive from the editor or a Raycast import. Malformed Markdown is reported per file
while valid files stay available.

The store runs only while the feature is enabled: launch starts it for an enabled feature, and a
user who never enables snippets pays for no load, no directory watcher and no event tap.

**Settings → Snippets** carries the feature switch and its launcher-visibility companion. The switch
is the whole feature, keyword expansion included — there is no separate expansion toggle — so
enabling it doubles as keyword-expansion consent: it confirms with an explanation first, then
requests Accessibility, and it ships off. Switching it off is a full teardown — the keyword listener,
the store and its watchers stop, and the launcher section disappears — while the files and the toggle
states survive for re-enabling. "Show in launcher" takes the section and the two Snippet commands out
of the launcher together; keyword expansion and the browser's shortcut keep working.
`snippetsShowInLauncher` travels in settings backups; `snippetsEnabled` deliberately does not, so an
import can never enable keystroke listening. `AppCore`'s settings sinks re-project on every change.

## Importing from Raycast

The encrypted `.rayconfig` flow in **Settings → Backup** can import Raycast's built-in snippets as
an independently selectable category. Tinycast reads `title`, `text` and the optional `keyword` from
the export's `snippets.snippets` collection. Invalid entries are skipped; valid entries are added in
source order without overwriting the existing library. Duplicate names receive the same filename
suffixes as snippets created in Tinycast, and duplicate keywords are preserved.

Imported snippets are enabled and launcher-visible, with their confirmation off. Importing
never enables automatic keyword expansion. A failure writing the snippet files is reported in the
import summary without aborting the settings and clipboard categories the user also selected.

## Markdown format

Frontmatter is optional. A file without an exact opening `---` line is treated entirely as the body,
with a display name derived from its filename.

Canonical output uses this order:

```markdown
---
name: "Meeting Notes"
keyword: "!notes"
enabled: true
show_confirmation: false
---

Template body
```

`name` is optional when reading and defaults from the filename, and `keyword` is optional. `enabled`
defaults to `true`; `show_confirmation` defaults to `false`.

String values must use double quotes. The codec escapes and decodes `\\`, `\"`, `\n`, `\r`, and
`\t`; unsupported escapes, unquoted strings, duplicate or unknown keys, non-exact delimiters, and
booleans other than lowercase `true` or `false` are rejected. Keys are matched case-insensitively;
there are no aliases, so a key Tinycast does not know names itself in the error.

Everything after the closing delimiter's line terminator is the body. Leading and trailing blank
lines, CR/LF choices, Unicode, and later lines containing `---` are preserved exactly when parsing.

## Template tokens

The template engine is **shared with [Quicklinks](quicklinks.md#placeholders)**, which expands a bare
string rather than a snippet record and asks for automatic percent-encoding. It is Foundation-only and
receives one captured expansion context: clipboard
history, selected text, clock, calendar, locale, time zone, and a UUID source. Everything the engine
needs is injected, so the whole placeholder surface is covered by the standalone harness. If arguments
require a prompt, the same context is reused afterward, so nothing can drift while the prompt is open.

The token set follows [Raycast's dynamic placeholders](https://manual.raycast.com/dynamic-placeholders)
so a migrated snippet keeps working.

| Token                                      | Result                                                                                                                                                                                                             |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `{clipboard}`                              | Captured plain-text clipboard value                                                                                                                                                                                |
| `{clipboard offset=1}`                     | Nth most recent clipboard text; `offset=1` is the one before the current                                                                                                                                           |
| `{selection}` · `{selectedText}`           | Captured selected text from the target app, when Accessibility can read it. `{selectedText}` is Raycast's spelling, accepted on the way in; `{selection}` is the canonical one and the only one **Insert…** writes |
| `{date}` · `{time}` · `{datetime}`         | Captured date / time / both, in the context locale                                                                                                                                                                 |
| `{day}`                                    | Weekday name                                                                                                                                                                                                       |
| `{uuid}`                                   | A fresh UUID per token                                                                                                                                                                                             |
| `{date format="yyyy-MM-dd"}`               | Any `DateFormatter` format                                                                                                                                                                                         |
| `{date locale="fr-FR"}`                    | Renders in another locale; cannot be combined with `format`                                                                                                                                                        |
| `{time offset="+3h +30m"}`                 | Signed offsets, space-separated: `m` minutes, `h` hours, `d` days, `M` months, `y` years                                                                                                                           |
| `{argument}`                               | An argument named `Argument`                                                                                                                                                                                       |
| `{argument name="Recipient"}`              | A named argument requested before expansion                                                                                                                                                                        |
| `{argument default="Hi"}`                  | Optional argument — the default expands without prompting                                                                                                                                                          |
| `{argument options="a, b, c"}`             | The prompt offers a picker instead of a text field                                                                                                                                                                 |
| `{snippet:Name}` · `{snippet name="Name"}` | Another snippet resolved by name, then keyword                                                                                                                                                                     |
| `{cursor}`                                 | Final insertion point                                                                                                                                                                                              |

The editor's **Insert…** menu lists every token above; parameters and modifiers are typed by hand.

Any value-producing token accepts a modifier pipeline, applied left to right:
`{clipboard | trim | uppercase}`. The modifiers are `uppercase`, `lowercase`, `trim`,
`percent-encode` (escapes everything outside RFC 3986's unreserved set), `json-stringify` (escapes for
use _inside_ a JSON string, without adding the quotes), and `raw`, which opts a value out of any
automatic formatting the _result_ asks for. A snippet asks for none, so `raw` is a no-op there; a
quicklink expanding into a URL percent-encodes every value, and `raw` is how a template opts one out.
`{cursor}` and snippet references are structural, so they take no modifiers.

A token Tinycast cannot parse — an unknown name, an unknown modifier, a duplicated or unsupported
parameter, an unterminated quote — is left in the text exactly as written rather than silently
dropped. `{browser-tab}` and `{calculator}` are not supported: the first needs a browser extension,
and the second has no defined input inside a snippet.

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

Every enabled snippet appears in launcher search while the pane's "Show in launcher" switch is on.
Its name and keyword are both searchable, scored in the same tiers as an app's name so a snippet ranks
above an app only when it genuinely matches better. Launcher expansion may interactively request
Accessibility because it begins from an explicit user action.

`Search Snippets` and `Create Snippet` are launcher commands of their own, and either switch takes
them out with the rows: "Show in launcher" off means the feature reaches launcher search not at all.
The browser stays reachable by its global shortcut, and the editor from the pane.

Automatic keyword expansion comes with the feature switch: enabling snippets in
**Settings → Snippets** first shows an explanation, then stores the flag and requests Accessibility if
it is missing. The flag is intentionally excluded from settings backups, so importing a backup cannot
enable keystroke listening.

**Accessibility is the only permission snippets need.** The keyword listener installs a listen-only
`CGEventTap`, which the Accessibility grant already authorizes — the same grant `HyperKeyTap` uses for
its _modifying_ tap, and the same one clipboard pasting needs. Input Monitoring is deliberately not
used: `CGPreflightListenEventAccess()` reports success whenever Accessibility is granted, so a second
permission would show as permanently granted while never appearing in System Settings, which cannot be
managed or revoked. It is managed where it always was, in **Settings → Permissions**.

Runtime status is explicit:

- **Off** — the feature is disabled and no keyword tap is retained.
- **Needs Accessibility** — the feature is enabled, but the grant, an active session, or a live event tap is missing.
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

## Search Snippets

`PaletteMode.snippets` is a dedicated browser, reached by the `Search Snippets` command or by the
global shortcut recorded in **Settings → Snippets**. Like Search Quicklinks it stays out of the Tab
cycle and exits with Escape or a bare backspace, and like the clipboard it splits into a list and a
preview.

The list is every **enabled** snippet — a disabled one is absent here exactly as it is absent from the
launcher — filtered by name *or* keyword. Substring matching, not the launcher's fuzzy scorer: this is
a library being browsed rather than a query racing apps and commands for a rank.

The preview shows the **raw template**, never an expansion. Expanding per selection would capture the
clipboard, read the target's selected text and burn a `{uuid}` on every arrow key, and a snippet
carrying `{argument}` would raise its prompt just to draw a pane. Beside it sits the name, keyword,
file name and character count.

↵ and the ⌘K menu's **Paste Snippet** both go through `SnippetCoordinator.expandSnippetFromPalette`,
which reads `previousApp` before hiding the panel and then calls the same `expandSnippet` funnel a
launcher row does — so template expansion, cursor placement, the Accessibility prompt, the
confirmation HUD and the pasteboard lease are the ones described below, not a second copy of them.
The rest of the menu is **Edit Snippet** and **Create Snippet**, which hand off to the pane's editor
through `AppCore.pendingSnippetEdit`, and **Show in Finder**.

`Create Snippet` is a launcher command as well as a menu row because the palette swallows ⌘K when a
screen has no rows: an empty library would otherwise open a browser with nothing to do.

## Confirmation HUD

The confirmation is per snippet and off by default: the only gate is `show_confirmation: true`, set
from the snippet's editor in **Settings → Snippets**. Nothing about it reaches settings backups.
The feature switch — which carries keyword-monitoring consent — is likewise excluded from backups.

`MessageHUDController` is shared rather than snippet-specific. It takes a message and a `DialogTone`
(defaulting to `.success`), the same tone vocabulary `DialogController`'s dialogs use, so a
custom command confirms a run through the same panel and the same tint rules; system actions'
success/info feedback uses it too (see [launcher.md](launcher.md#system-actions)). Its leading
trailing glyph, after the message, carries the tint. Its capsule uses `Theme.frosted(in:)`, the same
whitish-tinted glass as the rest of the app's floating controls (see [ui.md](../ui.md#liquid-glass)).

After either launcher or keyword delivery is confirmed, Tinycast may show a brief non-activating,
click-through overlay with the snippet name. The AppCore-owned controller replaces and restarts a
visible HUD on repeated deliveries, follows the existing cursor-screen preference, and never prompts
for permissions or activates Tinycast. Failed, cancelled, rejected, or prompt-cancelled expansions do
not report completion and therefore cannot show it.

## Text delivery and pasteboard safety

Delivery is one contract, in this order, and every clause below is a rule in it.

1. The focused element exposes `AXSelectedTextMarkerRange` → a renderer surface. Skip Accessibility.
2. The keyword is not at the caret yet → wait, up to 40 ms. Never arrives → events. Wrong → refuse.
3. Write over Accessibility, read the value back. Matches → done. Unchanged → events. Moved some
   other way → refuse.
4. Events: delete the keyword, then paste (long or multiline) or type in four-unit keystrokes.
5. Nothing landed → say so.

**Rule 1: a renderer's Accessibility surface is not authoritative.** Chromium and Monaco publish
selection as opaque text markers, and their `AXValue` either trails the editor by a few milliseconds
or — in VSCodium — stays empty and caret-zero indefinitely while the real editor holds the text. A
marker range is the reliable tell, so those targets never take the Accessibility write at all.
`accessibilityTextState` skips them for the same reason: a value that never moves cannot confirm a
paste either.

**Rule 2: too little text is not the same as the wrong text.** `AccessibilityReplacementPolicy`
`.pending` means the value is shorter than the keyword — the renderer has not caught up — and is
retried for up to eight 5 ms passes. `.rejected` means there was enough text and it was not the
keyword, which is a genuine mismatch and stops delivery. Only an automatic expansion waits; an
interactive one has no keyword race to lose. The convergence window is why an empty Monaco snapshot
falls through to events instead of reading as a mismatch.

**Rule 3: a `kAXErrorSuccess` from the setter is not evidence.** Chromium answers success and applies
nothing. `confirmsReplacement` rebuilds the exact string the write should have produced and compares
it to what the element reports. An unchanged value is `.unavailable`, so the event tiers still get
their turn instead of an "applied" message over untouched text; a value that changed into something
we did not write is `.rejected`, because events would then edit a document we can no longer describe.

**Rule 4** keeps the same permission, consent, Secure Event Input, target-app and cancellation gates.
The fallback deletes the keyword first, waits for deletion to settle, then inserts the expansion.
Short single-line expansions of at most 100 characters use Unicode keyboard events.

**A Unicode keystroke carries at most four UTF-16 units.** Blink stores one key event's text in a
fixed `WebKeyboardEvent::kTextLengthCap` array, so a Chromium target — Brave, Chrome, Electron, VS
Code, Slack — silently drops everything past the fourth unit of a single event. `UnicodeTypingChunk`
splits the text into four-unit keystrokes on scalar boundaries, because a lone surrogate half is not
text and a scalar never exceeds four units on its own. The chunks post through the same spaced,
re-gated loop the deletions use, so a target that goes away mid-word stops the rest.

Longer or multiline fallback text uses a temporary paste. Tinycast snapshots every item, type and data
payload, takes temporary ownership with the same item shape, and changes only the first plain-text
payload; restoration mutates that owned item back in place, never clearing the clipboard before a
fallible restore. A pasteboard with no string of its own — empty, or image-first — **borrows** instead:
Tinycast writes a single string item and restores by rewriting the snapshot, which is the one path that
clears first, because there is no original string item left to write back into. Declining the loan
there would have sent a long multiline expansion down the keystroke path a character at a time. The
pasteboard change count is checked before restoration, so a newer copy is never overwritten, and the
clipboard poller synchronizes to Tinycast's ownership changes so temporary or restored text is not
added as new history.

When Accessibility text state is readable, a long paste waits for evidence that the target changed.
If the editor cannot expose post-paste text state, a successfully posted paste is accepted only after
a conservative delay instead of being treated as a permanent failure. Cursor movement starts after
that confirmation or delay and after pasteboard restoration. Delivery completion is reported exactly
once only after the Accessibility replacement or event fallback (including requested cursor movement)
finishes successfully. Disabling automatic expansion or
terminating the app cancels pending delivery and deferred cursor movement; termination also completes
any pasteboard restoration still owned by Tinycast.

**Rule 5, and the keystroke that outruns it.** An automatic expansion is speculative, so the reader's
next real keystroke or click cancels whatever is still in flight — the listener reports every
non-ignored input to `cancelAutomaticExpansion`, and Tinycast's own tagged synthetic events classify
as `.ignored`, so a fallback never cancels itself. Delivery then settles exactly once either way:
Quick Actions raise a HUD and keep the reply on the clipboard, while snippets pass no failure handler
and stay as silent as before, because a speculative expansion that declined is not news.

## External edits and conflicts

`SnippetsStore` publishes repository snapshots and per-file issues on the main actor while all file
I/O runs off-main. Its debounced watcher observes external edits and atomic replacements, discards
stale load generations, and rearms after the directory is renamed, replaced, or deleted.

The editor keeps its draft in memory and writes only on **Save**; **New** creates no file until that
first save. Saves and deletes include the loaded source revision. All repository instances
for one channel share a serialized owner, and each mutation uses `NSFileCoordinator` before
revalidating the path and source revision immediately beside the atomic write or removal. Cooperative
writers therefore produce a conflict instead of being overwritten. macOS path-based APIs cannot
provide a true compare-and-swap against an uncooperative process that writes in the final interval
between revalidation and mutation, so Tinycast does not claim that impossible guarantee.

An editor open over a file that changed underneath it does not reconcile silently: the save is
rejected with the conflict above, and reopening the snippet shows what is now on disk.

## Standalone harness

Run the real model, codec, template engine, repository, keyword listener with a fake tap adapter, and
main-actor watcher against temporary roots:

```sh
./Scripts/run-tests.sh snippets-test
```

The delivery contract's two judgements — `keywordState` and `confirmsReplacement` — are pure, so the
harness drives renderer lag, a genuine mismatch, an empty editor snapshot, a false-success setter and
a write that landed elsewhere without an editor in the room. The tiers themselves are not: which rule
a given app takes is a manual check.

### Manual sweep

- Type a keyword in the **ChatGPT composer inside a Chromium browser**: it expands. This is rule 1 and
  rule 4 together — the composer is skipped over Accessibility and typed into in four-unit keystrokes.
- Type one in a **VSCodium editor pane**: it expands, where the Accessibility value stays empty.
- Type one in **Notes or Mail**: still the atomic Accessibility replacement, not events.
- Type a keyword, then keep typing before the expansion lands: the expansion is abandoned rather than
  landing mid-word.
- Type a keyword whose text the app changed underneath it: refused, with the keyword left alone.
