---
title: Snippets
description: Reusable Markdown templates with placeholders, arguments and keyword expansion.
---

A snippet is text you reuse, saved as a plain Markdown file that you can also edit by hand.

Paste a snippet from the launcher or the snippet browser, or type its keyword in any app and it
expands in place.

Turn snippets on in **Settings → Snippets**. They're **off** by default.

| Setting          | Default |
| ---------------- | ------- |
| Enable snippets  | Off     |
| Show in launcher | On      |

**Turning on the switch also counts as consent to keyword matching.** There's no separate prompt.
Tinycast first explains what keyword matching does, then asks for
[Accessibility](/docs/permissions#snippets-and-keystroke-matching).

Turning snippets off stops the keyword listener, the file watcher and the launcher rows. Your files
stay where they are.

Turning off **Show in launcher** hides snippets and the two snippet commands from search.
**Keyword expansion and the browser's shortcut keep working.**

`snippetsEnabled` is never included in [backups](/docs/reference/backup), so importing a backup can't
turn on keystroke listening.

## Commands

| Command         | Does                                |
| --------------- | ----------------------------------- |
| Search Snippets | Opens the snippet browser           |
| Create Snippet  | Opens the editor with a new snippet |

You can give both a global shortcut and an alias in **Settings → Snippets**.

## The snippet browser

**Search Snippets** lists every enabled snippet with a preview next to it. Type to filter by name or
keyword.

The preview shows the **template as written**, with its placeholders, along with the name, keyword,
shortcut, file name and character count. The preview never fills in placeholders, so browsing never
reads your clipboard or asks for an argument.

| Action (<kbd>⌘</kbd><kbd>K</kbd>) | Shortcut                      |
| --------------------------------- | ----------------------------- |
| Paste Snippet                     | <kbd>return</kbd>             |
| Edit Snippet                      | <kbd>⌘</kbd><kbd>E</kbd>      |
| Create Snippet                    | <kbd>⌘</kbd><kbd>N</kbd>      |
| Show in Finder                    | <kbd>⌘</kbd><kbd>return</kbd> |

Press <kbd>esc</kbd>, or <kbd>delete</kbd> in an empty search, to go back.

## Shortcuts

**Any snippet can have its own global shortcut.** Record it on the snippet's row in
**Settings → Snippets**. Pressing it pastes the snippet wherever you're typing, the same way the
launcher does: placeholders, arguments, the cursor position and the confirmation all work the same.

A snippet's shortcut does nothing while snippets are off or while that snippet is disabled.

The shortcut is tied to the file. If you rename or move the file outside Tinycast, or choose a
different snippets folder, the shortcut is cleared. Snippet shortcuts aren't included in backups.

## The file format

Each snippet is one Markdown file in Tinycast's Application Support folder. Frontmatter is optional.

```markdown
---
name: "Meeting Notes"
keyword: "!notes"
enabled: true
show_confirmation: false
---

## {date format="EEEE, d MMMM"}

Attendees: {argument name="Attendees"}

{cursor}
```

`name` defaults to the file name, and `keyword` is optional. `enabled` defaults to `true`, and
`show_confirmation` defaults to `false`.

Text values need **double quotes**. Keys aren't case-sensitive. Unknown keys, unquoted text,
repeated keys, and booleans other than lowercase `true` or `false` are rejected with a message that
names the problem.

Everything after the closing `---` is the body, and it's kept exactly as written, including blank
lines, line endings, Unicode characters and any later `---` lines.

Each channel has its own folder, so the stable and beta versions never share snippet files.

## Placeholders

| Token                          | Gives                                                              |
| ------------------------------ | ------------------------------------------------------------------ |
| `{clipboard}`                  | The clipboard contents, as plain text                              |
| `{clipboard offset=1}`         | An earlier clip; `1` is the one before the current one             |
| `{selection}`                  | The selected text in the app you were using                        |
| `{date}` `{time}` `{datetime}` | Today's date, the time, or both, in your locale                    |
| `{day}`                        | The name of the weekday                                            |
| `{uuid}`                       | A new UUID for each token                                          |
| `{date format="yyyy-MM-dd"}`   | Any date format                                                    |
| `{date locale="fr-FR"}`        | Another locale; can't be combined with `format`                    |
| `{time offset="+3h +30m"}`     | Shifted by `m` minutes, `h` hours, `d` days, `M` months, `y` years |
| `{argument}`                   | Asks you for a value, named "Argument"                             |
| `{argument name="Recipient"}`  | Asks for a named value                                             |
| `{argument default="Hi"}`      | Optional; uses the default without asking                          |
| `{argument options="a, b, c"}` | Asks you to pick from a list                                       |
| `{snippet:Name}`               | Another snippet, inserted inline                                   |
| `{cursor}`                     | Where the cursor goes afterward                                    |

These match [Raycast's dynamic placeholders](https://manual.raycast.com/dynamic-placeholders), so
snippets you import keep working. Raycast's `{selectedText}` and `{query}` also work, as
`{selection}` and `{argument}`. `{snippet name="Name"}` works the same as `{snippet:Name}`.

A value only needs quotes if it contains `|`. Without quotes, a value continues up to the next
`key=`, so `{date format=MMMM d, yyyy}` keeps its spaces.

The editor's **Insert…** menu lists every token. You type parameters and modifiers yourself.

### Modifiers

Chain modifiers from left to right: `{clipboard | trim | uppercase}`

Available modifiers: `uppercase` · `lowercase` · `trim` · `percent-encode` · `json-stringify` ·
`raw`

`json-stringify` escapes text for use inside a JSON string, without adding the quotes. `raw` only
matters in [quicklinks](/docs/launcher/quicklinks#encoding). `{cursor}` and snippet references don't
take modifiers.

### When a token is wrong

**If Tinycast can't read a token, it leaves it in the text exactly as you wrote it** instead of
silently removing it. So if you see `{arguemnt}` in your pasted text, you know where the typo is.

`{browser-tab}` and `{calculator}` aren't supported.

### Limits

Each argument is asked for once, in the order it first appears, including arguments inside
referenced snippets. Values are inserted as they are: text in a value that looks like a token isn't
expanded again.

Snippet references aren't case-sensitive and can be nested up to **five** levels deep. Tinycast
detects loops. A missing, looping or too-deeply nested reference stays in the text as a token.

All `{cursor}` tokens are removed, and the first one sets where the cursor goes.

## Keyword expansion

Give a snippet a keyword, and typing that keyword in any app replaces it with the snippet.

- Keywords **aren't case-sensitive, and the longest match wins**, so a more specific keyword takes
  priority.
- The typing buffer holds at most 256 characters. It resets when you switch apps, when Secure Event
  Input turns on, when you press arrow keys or shortcuts with modifiers, and after **15 seconds**
  without typing.
- If you keep typing before an expansion happens, the expansion is canceled so it can't land in the
  middle of a word.
- Right before deleting the keyword and inserting the text, Tinycast checks everything again. If
  anything changed, it leaves what you typed alone.

Settings shows the current status: **Off**, **Needs Accessibility** or **Active**.

Keywords never expand in Tinycast's own search field or in Settings. A keyword typed in
[Notes](/docs/features/notes) expands directly in the note.

### How the text gets inserted

Tinycast first tries a single replacement through Accessibility, then checks that it worked.

Some apps, like Chrome, VS Code, Slack and other Electron apps, don't support that properly, so
Tinycast types the text instead. Short, single-line expansions of up to 100 characters are typed as
keystrokes.

Longer or multi-line text is pasted using the clipboard for a moment. Tinycast saves your clipboard,
pastes only the snippet text, then restores your clipboard exactly. If you copied something new in
the meantime, Tinycast keeps your new copy. None of this appears in your
[clipboard history](/docs/features/clipboard).

## In the launcher

Enabled snippets appear in launcher search while **Show in launcher** is on. **Both the name and the
keyword are searchable**, and they rank the same way app names do.

<kbd>return</kbd> pastes the snippet.

## The editor

Changes aren't saved until you click **Save**. **New** doesn't create a file until you save for the
first time.

If the file changed on disk while you were editing, Tinycast **refuses to save and reports a
conflict** so it doesn't overwrite the other changes. Open the snippet again to see the current
version.

**Show confirmation** is set per snippet and is off by default. When it's on, a short message shows
the snippet's name after it's inserted. Failed or canceled expansions never show it.
