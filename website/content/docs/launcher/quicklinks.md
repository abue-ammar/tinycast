---
title: Quicklinks
description: Turn a URL, search, file or deeplink into a command, with values you fill in when you open it.
---

A quicklink is a saved destination that works like any other launcher entry. You can search for it,
give it a shortcut, and have it ask for a value, like a search term.

Turn quicklinks on in **Settings → Quicklinks**. They're **off** by default.

| Setting                       | Default    |
| ----------------------------- | ---------- |
| Enable quicklinks             | Off        |
| Show in launcher              | On         |
| Open in a new window          | Off        |
| When there's no selected text | Ask for it |
| Confirm before deleting       | On         |

While the feature is off, there's no Quicklinks section, no quicklink commands, and nothing opens.
**Your shortcuts stay saved**, so turning the feature back on restores all of them.

## Making one

Click **Add Quicklink** in Settings, or run the **Create Quicklink** command, to open the editor.

| Field               | What it does                                            |
| ------------------- | ------------------------------------------------------- |
| Name                | What you search for                                     |
| Link                | Where it goes, with any placeholders                    |
| Open With           | A specific app, or the default app                      |
| Icon                | A symbol, or **Automatic** to match the kind of link    |
| Pin to top          | Keeps it above your other quicklinks                    |
| Show in root search | Lists it in the main search with your apps and commands |

The **Insert…** menu adds placeholders for you.

## Destinations

Tinycast works out what kind of link you entered from its format:

| You write                                           | It becomes                        |
| --------------------------------------------------- | --------------------------------- |
| `~/Notes`, `/Users/...`, `file://...`               | A file or folder                  |
| `https://...`, `http://...`                         | A web page                        |
| `smb:` `afp:` `nfs:` `ftp:` `sftp:` `ftps:`         | A network location                |
| `spotify://`, `slack://`, `shortcuts://`, `mailto:` | A deeplink into an app            |
| `github.com/user/repo`                              | A web page, with `https://` added |

Two formats get special handling: a single letter followed by a colon is treated as a
**Windows drive letter**, and a name followed by a colon and only digits is treated as a
**host and port**.

## Placeholders

Quicklinks use the same placeholders as [snippets](/docs/features/snippets#placeholders):

```
https://google.com/search?q={argument}
https://github.com/search?q={argument name="Repository"}
https://translate.google.com/?text={selection}
https://chat.openai.com/?q={clipboard}
~/Notes/{date format="yyyy-MM-dd"}.md
```

`{cursor}` and `{snippet:…}` are left as written in a link, because a URL has no cursor. Raycast's
`{query}` works as `{argument}`.

### Encoding

Values inserted into a web link or deeplink are **encoded automatically**, so a search term with a
space or an `&` can't break the link. File paths are never encoded, so `%20` in a path stays `%20`.

`| raw` turns encoding off. It also lets the value decide what kind of link it is: a
`{clipboard | raw}` containing `file:///Users/me/notes.md` opens a file instead of a web page. This
can be useful but also surprising, so you have to turn it on yourself.

## Filling in values

When you select a quicklink that needs values, **small fields appear in the search bar** after what
you typed. The quicklink's row stays visible the whole time.

- <kbd>tab</kbd> moves from the search field through each field and back.
- <kbd>return</kbd> opens the quicklink. If a required field is empty, it moves to that field
  instead.
- A field with `options=` opens a menu of choices.
- <kbd>esc</kbd> moves from a field back to the search field.

A field only turns red after you've visited it and left it empty. Fields you haven't reached yet
aren't marked.

Values like `{clipboard}`, `{selection}` and `{date}` are read **when the link opens**. If you open a
quicklink with a shortcut while the palette is closed, `{selection}` reads from the app you were
using.

A shortcut for a quicklink that still needs values opens **Search Quicklinks** with that quicklink
selected and its first empty field ready for typing.

### When there is no selection

If a link uses `{selection}`, the **When there's no selected text** setting decides what happens:

- **Ask for it** (default): a **Selected Text** field appears. If you leave it empty, any real
  selection is still used; if you type something, your text replaces it.
- **Use the clipboard**: the clipboard contents are used instead of a selection.

## As a fallback

**A quicklink with an `{argument}` also appears under "Use … with"** at the bottom of every search.
What you typed fills in its first argument. See [Fallbacks](/docs/launcher/fallbacks).

## Opening

**Open With** saves a specific app. If you later uninstall that app, Tinycast shows a message with an
**Open with Default** button instead of silently switching to another app.

**Open in a new window** asks the browser to open a new window. Chrome and Firefox respect it, but
**Safari ignores it**. With the setting off, the link opens the way macOS normally opens links, which
usually reuses a tab.

Tinycast checks file and folder links before opening them, so if a folder was deleted, it tells you.

## Search Quicklinks

Quicklinks have their own launcher section. **Only the name is searchable**, along with any
[alias](/docs/launcher/aliases) you give it. The link itself isn't.

Pinned quicklinks come first, in the order you pinned them, followed by the rest sorted by name.
Pinning only affects the order within the Quicklinks section; pinned quicklinks don't appear above
your apps.

To change a quicklink from the launcher, select it and press <kbd>⌘</kbd><kbd>E</kbd>
(**Edit Quicklink**).

The **Search Quicklinks** command opens a screen with the list on the left and details on the right:
the link, the app it opens with, its shortcut and when you created it.

| Action                          | Shortcut                             |
| ------------------------------- | ------------------------------------ |
| Open Quicklink                  | <kbd>return</kbd>                    |
| Open With Default App           | <kbd>⌘</kbd><kbd>return</kbd>        |
| Copy Link                       | <kbd>⌃</kbd><kbd>⌘</kbd><kbd>C</kbd> |
| Edit Quicklink                  | <kbd>⌘</kbd><kbd>E</kbd>             |
| Duplicate Quicklink             | <kbd>⌘</kbd><kbd>D</kbd>             |
| Pin / Unpin Quicklink           | <kbd>⌘</kbd><kbd>.</kbd>             |
| Show in Finder                  | <kbd>⌘</kbd><kbd>F</kbd>             |
| Delete Quicklink                | <kbd>⌘</kbd><kbd>delete</kbd>        |

**Open With Default App** only appears when the quicklink opens with a specific app, and
**Show in Finder** only appears for files and folders.

**Copy Link** is available in the actions menu (<kbd>⌘</kbd><kbd>K</kbd> or right-click) in both the
launcher and Search Quicklinks, or directly with <kbd>⌃</kbd><kbd>⌘</kbd><kbd>C</kbd>.
It copies the saved destination without opening it. Placeholders
such as `{argument}` and `{clipboard}` stay as written, even when you've filled in values.

## Three ways to hide a quicklink

From broadest to narrowest:

1. Turning off **Show in launcher** in Settings removes all quicklinks and quicklink commands from
   search.
2. Clearing the **Enabled** checkbox on a quicklink's row in Settings turns off that one quicklink
   but keeps its shortcut and settings.
3. Turning off **Show in root search** keeps a quicklink out of the main search, but you can still
   open it from Search Quicklinks or with its shortcut. In the launcher,
   <kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd> (**Hide from Root Search**) turns it off for the selected
   quicklink.

Editing a quicklink keeps its shortcut, favorite, visibility and learned ranking.
**Duplicating creates a new quicklink**, so the copy doesn't get the original's shortcut.

## Import and export

**Import Quicklinks** and **Export Quicklinks** use a simple JSON file you can edit by hand. A plain
list also works, and only `name` and `link` are required.

```json
{
  "version": 1,
  "quicklinks": [
    {
      "name": "GitHub search",
      "link": "https://github.com/search?q={argument name=\"Query\"}"
    }
  ]
}
```

A quicklink is skipped as a duplicate if its **name or link** matches one you already have, or one
earlier in the same file. The summary shows how many were skipped.

You can also import quicklinks from a [Raycast export](/docs/reference/import-from-raycast).

## Where they're stored

Quicklinks are stored in `quicklinks.sqlite3` in Tinycast's Application Support folder. If that file
can't be opened, Tinycast **reports the problem and never deletes the file**, because your links
can't be rebuilt from anywhere else.
