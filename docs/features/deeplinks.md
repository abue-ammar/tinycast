# Deeplinks

Every launcher row that can take a hotkey can also be run by URL, and so can a note, a saved AI chat
and a one-off window size. Karabiner-Elements, a Shortcut, a script, a Stream Deck or a web page can
drive Tinycast without a chord of its own:

```sh
open -g "tinycast://command/clipboard-history"
open -g "tinycast://command/search-files?fallbackText=~/Downloads/"
```

A link can carry input: text, field values and an editor's contents. **Copy Deeplink** gives the
exact link, typed fields included, so nobody has to build one by hand.

`Features/DeepLinks/` holds:

- `DeepLink` — the parsed link, and the URL builders (`Model/`).
- `DeepLinkInput` — `fallbackText`, `arguments` and `context`: decoded, size-checked, encoded back
  (`Model/`).
- `DeepLinkConsentPolicy` — which links ask, and the key Always Allow stores (`Model/`).
- `DeepLinkSource` — outside, or a quicklink of ours, and what each may run (`Model/`).
- `CustomWindowSize+DeepLink` — a window size spelled out in a link (`Model/`).
- `DeepLinkCoordinator` — on `AppCore`. It parses, gates, asks, and hands the target to its feature
  (`UI/`).
- `AllowedDeepLinksSection` — Settings → General → Deeplinks, where an Always Allow is removed
  (`Settings/`).

`ShortcutDeepLink` (`HotKeys/UI/`) is the environment value that puts Copy Deeplink on every
Settings shortcut field; only the Settings window sets it.

## Invariants

- **A link is a hotkey press plus input.** A link with no input resolves to the same `HotKeyAction`
  a recorded shortcut fires and goes to `HotKeyManager.perform`. It toggles where a shortcut
  toggles. Input only reaches a target through that feature's own coordinator.
- **One gate for hotkeys and links.** `AppCore.allowsHotKeyAction(_:)` is the category check for
  both. A link it refuses shows a HUD that names the command; it never fails silently.
- **One mapping from row to action.** `HotKeyAction(entryID:)` turns a row ID into an action, and
  `HotKeyAction.entryID` turns it back. `DeepLink.url(forEntryID:scheme:input:)` returns nil for a
  row no link can run, so a copied link always resolves.
- **The index is never consulted.** A link works from the ID alone, so a command hidden from search,
  or a link opened at login before the first scan, still runs.
- **A link that launches the app waits for `start`.** `AppCore.handleOpenURL` queues until every
  handler is wired, then runs the queue in order.
- **The scheme is the channel's own.** Release answers `tinycast://`, Debug `tinycast-dev://`, set by
  `TINYCAST_URL_SCHEME` in `project.yml` and read through `AppURLScheme`. `raycast://` and
  `com.raycast:` never reach a built-in.
- **The built-in router never touches extension types.** `DeepLinkCoordinator.handles(_:)` leaves
  the `extensions` host and every Raycast scheme to the extension branch of
  `AppCore.handleOpenURL`. Copy Deeplink asks `ExtensionCoordinator.deepLink(forEntryID:arguments:)`
  for an extension row, which builds it in the channel's scheme. Moving extensions out of the app
  means deleting that one branch.
- **A link never runs shell text unasked.** Open in Browser, Run Shell Command and Quit have no link,
  and any link from outside that carries input asks first, so typed text is never one Return from
  a fallback row.
- **A create link never saves on its own.** One object opens a filled-in editor; a list asks before
  it adds anything.
- **A quicklink never opens a quicklink.** Its own-scheme link runs in-process and synchronously, so
  a quicklink that reached itself would recurse forever. `DeepLinkSource.mayRun(_:)` refuses it.
- **Consent never travels.** `deepLinkAllowedEntryIDs` is excluded from backups and from
  `settings.json`, since each entry lets any app or web page run a command unasked.

## Links

| Link                                        | Does                                                            |
| ------------------------------------------- | --------------------------------------------------------------- |
| `tinycast://`                               | Opens the launcher                                              |
| `tinycast://search?fallbackText=2%2B2`      | Opens the launcher with the text typed                          |
| `tinycast://command/<slug>`                 | Runs a built-in command                                         |
| `tinycast://window-command/left-half`       | Runs a window command                                           |
| `tinycast://system-action/lock-screen`      | Runs a system action                                            |
| `tinycast://window-size/<uuid>`             | Applies a saved window size                                     |
| `tinycast://window-size?arguments={…}`      | Applies a size spelled out in the link                          |
| `tinycast://window-layout/<uuid>`           | Applies a window layout                                         |
| `tinycast://window-room/<uuid>`             | Enters a room                                                   |
| `tinycast://quick-action/<uuid>`            | Runs a custom Quick Action                                      |
| `tinycast://custom-command/<uuid>`          | Runs a custom command                                           |
| `tinycast://quicklink/<uuid>`               | Opens a quicklink                                               |
| `tinycast://apple-shortcut/<uuid>`          | Runs an Apple Shortcut                                          |
| `tinycast://snippet/<percent-encoded path>` | Expands a snippet                                               |
| `tinycast://note/<file name>`               | Opens that note                                                 |
| `tinycast://chat/<uuid>`                    | Opens that saved chat in the AI Chat window                     |
| `tinycast://settings/<tab>`                 | Opens Settings on a tab (`SettingsTab.slug`)                    |
| `tinycast://extensions/<owner>/<ext>/<cmd>` | Extension command, see [extensions.md](extensions.md#deeplinks) |

A row's path is its `AppEntry.id` with the first `:` turned into `/`: `command:clipboard-history`
becomes `tinycast://command/clipboard-history`. Built-in commands use their `CommandID` slug. Quick
AI keeps the slug it shipped with, `ai-chat`, and the AI Chat window is `ai-chat-window`. Rows you
create are keyed by UUID, which survives a rename. A note is known only by its file name, so
renaming a note breaks its link; the store then reports the missing file.

Applications and System Settings panes have no link: `open -a` and `x-apple.systempreferences:`
already cover them.

## Input

The parameter names are case-insensitive:

- **`fallbackText`** — text for the target's first field.
- **`arguments`** — URL-encoded JSON. An object fills fields by name, an array fills them in order.
- **`context`** — URL-encoded JSON for the create commands: one object, or a list of them.

Values are coerced to the text a field would hold: numbers and booleans become their text, `null`
becomes empty. **Malformed JSON, a nested value or a parameter over 64 KB (UTF-8 bytes) refuses the
whole link** with a HUD; a link never runs without the input it asked for. Other parameters are
ignored, because each built-in already knows whether it shows a screen.

| Target                       | Input                                                                                        |
| ---------------------------- | -------------------------------------------------------------------------------------------- |
| `search`                     | `fallbackText` is typed into the launcher                                                    |
| A search screen (list below) | `fallbackText` opens it searching; a seeded screen never toggles shut                        |
| `command/ai-chat`            | `fallbackText` is typed into Quick AI, never sent                                            |
| `command/ai-chat-window`     | `fallbackText` joins the window's unsent line, never sent                                    |
| `command/create-quicklink`   | `context` `{name, link, openWith}`, or a list of them; `fallbackText` is the link            |
| `command/create-snippet`     | `context` `{name, text, keyword}`, or a list of them; `fallbackText` is the text             |
| `command/create-note`        | `context` `{text}` or `fallbackText` becomes the new note's text                             |
| `quicklink/<uuid>`           | `arguments` by argument name; `fallbackText` fills the first required one                    |
| `custom-command/<uuid>`      | `arguments` as `["a", "b"]`, or by argument name; `fallbackText` is `$1`                     |
| `system-action/set-volume`   | `arguments` `{volume}`, `["50"]` or `fallbackText`: `0`–`100`, `%` allowed; skips the picker |
| `window-size`                | `arguments` `{width, height, anchor, x, y}`: `1200` is points, `60%` a share of the screen   |

The search screens are `clipboard-history`, `search-emoji`, `calculator-history`,
`search-quicklinks`, `search-files`, `define`, `search-snippets`, `search-custom-commands`,
`search-menu-items` and `switch-windows`. A missing quicklink or custom-command argument opens the
row's fields, as a hotkey with no selection does. Any other target ignores its input.

- A `create-*` list asks once, then adds every item it can, skipping duplicates as a file import
  does, and reports the count in a HUD.
- `openWith` is kept only when it names an installed app's bundle ID.
- A window size refuses, rather than clamps, a value outside what a saved size allows. `anchor` is a
  `WindowLayoutAnchor` raw value (`top-left`, `center`, …) and `x`/`y` shift it in points.
- Create Snippet with no input — from a link, a hotkey or the launcher — starts from the text
  selected in the app in front, read through Accessibility (`AccessibilityText.selection(in:)`),
  never by sending ⌘C.

## Consent

`DeepLinkConsentPolicy.requiresConsent(_:input:)` decides. **A link from outside asks first when it
carries input, or when its target acts outside Tinycast.** The second half is an exhaustive switch,
so a new command fails to build until it is classed:

- **Never asks without input**: anything that only opens a Tinycast screen or editor — search
  screens, Settings, notes, chats, the create commands, Quick AI.
- **Always asks**: window commands and sizes, layouts, rooms, system actions, quicklinks, snippets,
  custom commands, Apple Shortcuts, custom Quick Actions, the AI text actions, Paste Sequentially,
  Open Camera, the meeting commands and Capture Window Layout.

Input always asks because a page chose it: typed into the launcher it is one Return from a fallback
row, and as arguments it reaches a script.

The question names the target, shows the input (`DeepLinkInput.summary`, cut at 160 characters) and
offers **Always Allow**, **Run Once** and **Cancel**. **Cancel is the default**, because the dialog
takes key and a stray Return must not run anything. A target that does not exist is reported as an
unknown link before any question, so a page cannot learn what exists by asking.

Always Allow stores `DeepLinkConsentPolicy.key(entryID:input:)`: the row alone, or the row with its
exact input, the row's ID percent-encoded so a `?` in a snippet path cannot fake the split. A grant
never covers different input, so a Karabiner key with fixed text asks once and an attacker's text
still asks. A size spelled out in a link is one target, `window-size`, whatever the size.
Destructive system actions still ask their own question after it. One question shows at a time: a
link that arrives meanwhile is logged and dropped. The gate is checked again after the answer, so a
feature turned off during the question still wins.

A link Tinycast opens itself — a quicklink whose link is the channel's own scheme — runs in-process
with `source: .tinycast`. It never asks, because the reader chose it in Tinycast. It never goes
through LaunchServices either.

## Copy Deeplink

- **Launcher rows**: ⇧⌘C, or ⌘K on the row. Values typed into the row's argument fields ride along:
  by name for a quicklink or an extension, in order for a custom command. Empty fields are dropped.
- **Settings**: right-click any shortcut field. The link is the row's, with no fields typed.
- **Notes**: the link button on a note switcher row.
- **AI Chat**: the sidebar's menu on a saved chat, and the window's menu.

## Focus

A plain `open` (without `-g`) activates Tinycast before the link arrives. Tinycast is an accessory
app, so it does not take the menu bar, and the menu-bar owner is still the app the reader was in.
`FrontmostApp.current` returns that app when Tinycast itself is frontmost with no window of its own
in key. `PaletteCoordinator.targetApp`, `WindowTarget.current()` and the palette's record of the app
it covered all use it, so a window command, or a paste from a palette a link opened, reaches the
right app. Pasting with the palette closed still needs the target app active, so snippets and Paste
Sequentially want `open -g`.

## Karabiner-Elements

```json
{
  "description": "Hyper+V opens Tinycast clipboard history",
  "manipulators": [
    {
      "type": "basic",
      "from": {
        "key_code": "v",
        "modifiers": { "mandatory": ["left_command", "left_control", "left_option", "left_shift"] }
      },
      "to": [{ "shell_command": "open -g 'tinycast://command/clipboard-history'" }]
    }
  ]
}
```
