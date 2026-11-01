---
title: Deeplinks
description: Run any command from a tinycast:// link, with text and arguments, from Karabiner, Shortcuts, scripts or a web page.
---

**Anything you can give a shortcut, you can also run from a link.** Use links from
Karabiner-Elements, Shortcuts, a Stream Deck, a script or a web page:

```sh
open -g "tinycast://command/clipboard-history"
```

## Get a link

Select a row in the launcher and press <kbd>⇧</kbd><kbd>⌘</kbd><kbd>C</kbd>, or open its actions
with <kbd>⌘</kbd><kbd>K</kbd> and choose **Copy Deeplink**. Copy the link instead of typing it: rows
you create, like quicklinks, use an ID that stays the same when you rename them.

Apps and System Settings panes have no Tinycast link. Use `open -a` and `x-apple.systempreferences:`
for them.

## What links can do

| Link                                   | What it does                                          |
| -------------------------------------- | ----------------------------------------------------- |
| `tinycast://`                          | Opens the launcher                                    |
| `tinycast://search?fallbackText=2%2B2` | Opens the launcher with `2+2` typed                   |
| `tinycast://command/clipboard-history` | Runs a built-in command                               |
| `tinycast://window-command/left-half`  | Moves the front window                                |
| `tinycast://system-action/lock-screen` | Runs a [system action](/docs/launcher/system-actions) |
| `tinycast://settings/permissions`      | Opens Settings on a pane                              |

A link to a command that opens a screen works like its shortcut: open it twice and the screen
closes.

## Send text and arguments

Links take the same parameters as Raycast's. Encode their values for a URL.

- **`fallbackText`** types text into the command's first field. For example,
  `tinycast://command/search-files?fallbackText=~/Downloads/` opens Search Files already searching.
- **`arguments`** fills a quicklink's or custom command's fields. Use JSON: an object fills fields by
  name, a list fills them in order.
- **`context`** fills an editor. For example,
  `tinycast://command/create-quicklink?context={"name":"Docs","link":"https://example.com"}` opens a
  new quicklink already filled in. Nothing is saved until you press Save.

`fallbackText` works with Clipboard History, Search Emoji & Symbols, Calculator History, Search
Quicklinks, Search Files, Define Word, Search Snippets, Search Custom Commands, Search Menu Items,
Switch Windows, Create Snippet and Create Note. In Quick AI it types your text, but does not send it.

If a link's JSON is broken, Tinycast says it can't open the link and runs nothing.

## Links that ask first

**A link from another app or a web page asks before it acts outside Tinycast.** That includes window
commands, system actions, quicklinks, snippets, custom commands and Apple Shortcuts. You can choose:

- **Always Allow**: run it now, and never ask again for this command.
- **Run Once**: run it now, and ask next time.
- **Cancel**: run nothing.

A link that only opens a Tinycast screen, like Clipboard History or Settings, never asks. Restart,
Shut Down and other big system actions still ask their own question too.

To make a command ask again, remove it in **Settings → General → Deeplinks**. This list is never
part of a backup.

A quicklink that points to a `tinycast://` link runs it without asking, because you made it.

## Karabiner-Elements

Use `open -g`, so the link runs without bringing Tinycast forward:

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

Window commands also work with a plain `open`. Snippets and Paste Sequentially need `open -g`, so
the text goes to the app you're in.

## Extension links

Extension commands use their own links, like `raycast://extensions/<owner>/<extension>/<command>`.
See [Compatibility](/docs/extensions/compatibility).
