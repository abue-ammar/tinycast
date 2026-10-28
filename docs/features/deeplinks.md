# Deeplinks

Every launcher row that can take a hotkey can also be run by URL, so Karabiner-Elements, a
Shortcut, a script or another launcher can drive Tinycast without a chord of its own:

```sh
open -g "tinycast://command/clipboard-history"
```

The link is the row's `AppEntry.id` with its first `:` turned into `/`, which keeps it readable
and stable: `command:clipboard-history` becomes `tinycast://command/clipboard-history`. **Copy
Deeplink** (⇧⌘C, or ⌘K on the row) puts the exact link on the clipboard, so nobody has to
construct one by hand.

## Invariants

- **A deeplink is a hotkey press.** `EntryDeepLink.action(for:)` resolves the URL to the same
  `HotKeyAction` a recorded shortcut fires, and `AppCore.handleOpenURL` hands it to
  `HotKeyManager.perform`. A deeplink therefore toggles where a shortcut toggles, and does nothing
  while its feature is switched off. There is no second dispatch path to keep in step.
- **One mapping from row to action.** `HotKeyAction(entryID:)` is the only place that turns a row ID
  into an action. `AppEntry.hotKeyAction` calls it too, so a row is offered a link exactly when it
  can be offered a shortcut. `EntryDeepLink.url(forEntryID:)` returns nil for any row it cannot
  run, so a copied link always resolves.
- **The index is never consulted.** Resolution works from the ID alone. A command unlisted from
  search, or a link opened at login before the first scan, still runs, as its shortcut would.
- **Built-in links are `tinycast://` only.** `raycast://` and `com.raycast:` stay extension links,
  so a Raycast-shaped URL never reaches a built-in command by accident.

## Links

| Row                          | Link                                         |
| ---------------------------- | -------------------------------------------- |
| Built-in command             | `tinycast://command/clipboard-history`       |
| Window command               | `tinycast://window-command/left-half`        |
| System action                | `tinycast://system-action/lock-screen`       |
| Custom window size           | `tinycast://window-size/<uuid>`              |
| Window layout                | `tinycast://window-layout/<uuid>`            |
| Room                         | `tinycast://window-room/<uuid>`              |
| Custom Quick Action          | `tinycast://quick-action/<uuid>`             |
| Custom command               | `tinycast://custom-command/<uuid>`           |
| Quicklink                    | `tinycast://quicklink/<uuid>`                |
| Apple Shortcut               | `tinycast://apple-shortcut/<uuid>`           |
| Snippet                      | `tinycast://snippet/<percent-encoded path>`  |
| Extension command            | `tinycast://extensions/<owner>/<ext>/<cmd>`  |
| The launcher                 | `tinycast://`                                |

Built-in commands use their `CommandID` slug, such as `show-notes` or `search-emoji`. Quick AI keeps
the slug it shipped with, `ai-chat`, and the AI Chat window is `ai-chat-window`. Window commands and
system actions use their `ID` raw values. Rows you create are keyed by UUID, which survives a
rename. Copy the link instead of typing one.

The query-driven commands (Open in Browser, Run Shell Command) and Quit have no shortcut, and so no
link.
Applications and System Settings panes have no link either: `open -a` and
`x-apple.systempreferences:` already cover them.

Extension commands keep the Raycast-compatible form documented in
[extensions.md](extensions.md#deeplinks), with its `arguments` and `fallbackText` parameters.
Anything else on a claimed scheme, including an unknown or mistyped link, reopens the launcher.

## Karabiner-Elements

Use `open -g` so the link reaches Tinycast without activating it. A plain `open` can make Tinycast
the frontmost app, and window commands act on the frontmost app's window.

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
