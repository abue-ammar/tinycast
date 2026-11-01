# Deeplinks

Every launcher row that can take a hotkey can also be run by URL. Karabiner-Elements, a Shortcut, a
script, a Stream Deck or a web page can drive Tinycast without a chord of its own:

```sh
open -g "tinycast://command/clipboard-history"
open -g "tinycast://command/search-files?fallbackText=~/Downloads/"
```

A link can also carry input, in Raycast's parameter names. **Copy Deeplink** (⇧⌘C, or ⌘K on the
row) puts a row's exact link on the clipboard, so nobody has to build one by hand.

`Features/DeepLinks/` holds:

- `DeepLink` — the parsed link (`Model/`). It turns a URL into a target and its input, and builds a
  row's URL.
- `DeepLinkInput` — `fallbackText`, `arguments` and `context`, decoded and size-checked (`Model/`).
- `DeepLinkConsentPolicy` — which targets ask before a link from outside runs them (`Model/`).
- `DeepLinkCoordinator` — on `AppCore`. It parses, gates, asks, and hands the target to its feature
  (`UI/`).
- `AllowedDeepLinksSection` — Settings → General → Deeplinks, where an Always Allow is removed
  (`Settings/`).

## Invariants

- **A link is a hotkey press plus input.** A link with no input resolves to the same `HotKeyAction`
  a recorded shortcut fires and goes to `HotKeyManager.perform`. It toggles where a shortcut
  toggles. Input only reaches a target through that feature's own coordinator.
- **One gate for hotkeys and links.** `AppCore.allowsHotKeyAction(_:)` is the category check for
  both. A link it refuses shows a HUD that names the command; it never fails silently.
- **One mapping from row to action.** `HotKeyAction(entryID:)` turns a row ID into an action, and
  `HotKeyAction.entryID` turns it back. `DeepLink.url(forEntryID:scheme:)` returns nil for a row no
  link can run, so a copied link always resolves.
- **The index is never consulted.** A link works from the ID alone, so a command hidden from search,
  or a link opened at login before the first scan, still runs.
- **The scheme is the channel's own.** Release answers `tinycast://`, Debug `tinycast-dev://`, set by
  `TINYCAST_URL_SCHEME` in `project.yml` and read through `AppURLScheme`. `raycast://` and
  `com.raycast:` never reach a built-in.
- **The built-in router never touches extension types.** `DeepLinkCoordinator.handles(_:)` leaves
  the `extensions` host and every Raycast scheme to the extension branch of
  `AppCore.handleOpenURL`. Copy Deeplink asks `ExtensionCoordinator.deepLink(forEntryID:)` for an
  extension row. Moving extensions out of the app means deleting that one branch.
- **A link never carries shell text.** Open in Browser, Run Shell Command and Quit have no link. A
  custom command takes arguments as `$1…$3`, never spliced into its script.
- **A create link never saves.** `create-quicklink` and `create-snippet` open a filled-in editor.
  Nothing is written until the reader saves.
- **A link from outside that acts outside Tinycast asks first.** See [Consent](#consent).
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
| `tinycast://window-size/<uuid>`             | Applies a custom window size                                    |
| `tinycast://window-layout/<uuid>`           | Applies a window layout                                         |
| `tinycast://window-room/<uuid>`             | Enters a room                                                   |
| `tinycast://quick-action/<uuid>`            | Runs a custom Quick Action                                      |
| `tinycast://custom-command/<uuid>`          | Runs a custom command                                           |
| `tinycast://quicklink/<uuid>`               | Opens a quicklink                                               |
| `tinycast://apple-shortcut/<uuid>`          | Runs an Apple Shortcut                                          |
| `tinycast://snippet/<percent-encoded path>` | Expands a snippet                                               |
| `tinycast://settings/<tab>`                 | Opens Settings on a tab (`SettingsTab.slug`)                    |
| `tinycast://extensions/<owner>/<ext>/<cmd>` | Extension command, see [extensions.md](extensions.md#deeplinks) |

The path is the row's `AppEntry.id` with its first `:` turned into `/`: `command:clipboard-history`
becomes `tinycast://command/clipboard-history`. Built-in commands use their `CommandID` slug. Quick
AI keeps the slug it shipped with, `ai-chat`, and the AI Chat window is `ai-chat-window`. Rows you
create are keyed by UUID, which survives a rename.

Applications and System Settings panes have no link: `open -a` and `x-apple.systempreferences:`
already cover them.

## Input

The names match Raycast's, and are case-insensitive:

- **`fallbackText`** — text for the target's first field.
- **`arguments`** — URL-encoded JSON. An object fills fields by name, an array fills them in order.
- **`context`** — a URL-encoded JSON object. `launchContext` is accepted too, and wins over
  `context`, as in Raycast.

Values are coerced to the text a field would hold: numbers and booleans become their text, `null`
becomes empty. **Malformed JSON, a nested value or a parameter over 64 KB refuses the whole link**
with a HUD; a link never runs without the input it asked for. Other parameters, `launchType`
included, are ignored, because each built-in already knows whether it shows a screen.

| Target                       | Input                                                                             |
| ---------------------------- | --------------------------------------------------------------------------------- |
| `search`                     | `fallbackText` is typed into the launcher                                         |
| A search screen (list below) | `fallbackText` opens it searching; a seeded screen never toggles shut             |
| `command/ai-chat`            | `fallbackText` is typed into Quick AI, never sent                                 |
| `command/create-quicklink`   | `context` `{name, link, openWith}`; `fallbackText` is the link                    |
| `command/create-snippet`     | `context` `{name or title, text or snippet, keyword}`; `fallbackText` is the text |
| `command/create-note`        | `context` `{text}` or `fallbackText` becomes the new note's text                  |
| `quicklink/<uuid>`           | `arguments` by argument name; `fallbackText` fills the first required one         |
| `custom-command/<uuid>`      | `arguments` as `["a", "b"]`, or by argument name; `fallbackText` is `$1`          |

The search screens are `clipboard-history`, `search-emoji`, `calculator-history`,
`search-quicklinks`, `search-files`, `define`, `search-snippets`, `search-custom-commands`,
`search-menu-items` and `switch-windows`. A missing quicklink or custom-command argument opens the
row's fields, as a hotkey with no selection does. Any other target ignores its input.
`openWith` is kept only when it names an installed app's bundle ID.

## Consent

`DeepLinkConsentPolicy.requiresConsent(_:)` decides, by exhaustive switch, so a new command fails to
build until it is classed:

- **Never asks**: anything that only opens a Tinycast screen or editor — search screens, Settings,
  the create commands, notes, Quick AI.
- **Asks once**: anything that acts outside Tinycast — window commands, layouts, rooms, system
  actions, quicklinks, snippets, custom commands, Apple Shortcuts, custom Quick Actions, the AI text
  actions, Paste Sequentially, Open Camera, the meeting commands and Capture Window Layout.

The question offers **Always Allow**, **Run Once** and **Cancel**. Always Allow stores the row's
entry ID in `deepLinkAllowedEntryIDs`. Destructive system actions still ask their own question after
it. One question shows at a time: a link that arrives meanwhile is logged and dropped, as Raycast
does. The gate is checked again after the answer, so a feature turned off during the question still
wins.

A link Tinycast opens itself — a quicklink whose link is the channel's own scheme — runs in-process
with `source: .tinycast`. It never asks, because the reader chose it in Tinycast. It never goes
through LaunchServices either.

## Focus

A plain `open` (without `-g`) activates Tinycast before the link arrives. Tinycast is an accessory
app, so it does not take the menu bar, and the menu-bar owner is still the app the reader was in.
`FrontmostApp.current` returns that app when Tinycast itself is frontmost. `PaletteCoordinator.targetApp`
and `WindowTarget.current()` use it, so a window command from a plain `open` moves the right window.
Pasting needs the target app to be active, so snippets and Paste Sequentially still want `open -g`.

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
