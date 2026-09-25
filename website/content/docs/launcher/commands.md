---
title: Commands
description: Every built-in command, and the shell commands you write yourself.
---

Commands are things Tinycast does, reachable by name from the launcher. Some are built in. Others
are shell commands you write.

## Built-in commands

Every built-in command lives in exactly one Settings pane. A feature's commands sit in that
feature's own pane, and only appear while the feature is on. The rest live in **Settings → Commands**.

| Pane                                               | Commands                                                                                                                                                                                           |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [AI](/docs/ai)                                     | AI Chat                                                                                                                                                                                            |
| [Quick Actions](/docs/ai/quick-actions)            | Fix Grammar · Rewrite · Translate · Summarize                                                                                                                                                      |
| [Clipboard](/docs/features/clipboard)              | Clipboard History                                                                                                                                                                                  |
| [Emoji & Symbols](/docs/features/emoji)            | Search Emoji & Symbols                                                                                                                                                                             |
| [File Search](/docs/features/file-search)          | Search Files                                                                                                                                                                                       |
| [Navigation](/docs/features/navigation)            | Switch Windows · Search Menu Bar Items                                                                                                                                                             |
| [Calendar](/docs/features/calendar)                | Join Next Meeting · My Schedule · Create Event · Copy Meeting Link · Open in Calendar                                                                                                              |
| [Notes](/docs/features/notes)                      | Show Notes · Create Note · Search Notes                                                                                                                                                            |
| [Window Management](/docs/features/window-layouts) | Create Window Layout · Create Layout from Current Windows · Switch Room · Create Room · Show All Windows                                                                                                                                          |
| [Quicklinks](/docs/launcher/quicklinks)            | Create Quicklink · Search Quicklinks · Import Quicklinks · Export Quicklinks                                                                                                                       |
| [Snippets](/docs/features/snippets)                | Search Snippets · Create Snippet                                                                                                                                                                   |
| Commands                                           | Calculator History · [Open Camera](/docs/features/camera) · Export Backup · Import Backup · Import from Raycast · Check for Updates · Settings · About Tinycast · Support Tinycast · Quit Tinycast |

Two more appear only for what you type: **Open in Browser** and **Run Shell Command**. See
[Fallbacks](/docs/launcher/fallbacks).

Each command's row has a launcher checkbox, a shortcut recorder and an alias field.

**Every built-in command can take a global shortcut**, except Open in Browser and Run Shell Command,
which need text to work on, and Quit Tinycast, so no stray key press can quit the app.

A command that opens a screen works like a toggle: press its shortcut again to close it.

**Enable Commands** at the top of Settings → Commands switches off every command listed in that pane,
along with their shortcuts. Unticking one row only hides it from search; its shortcut keeps working.

## Custom commands

Give a shell command a name, and run it from search or its own global shortcut.

**Settings → Commands → Custom Commands** holds the switch. It ships **off**.

| Setting                | Default |
| ---------------------- | ------- |
| Enable custom commands | Off     |
| Show in launcher       | On      |

**Show in launcher** off hides the section but keeps every shortcut working.

Only the **name** is searchable. The command itself is not, so you cannot run something by
half-remembering its flags.

Each command has an **Enabled** checkbox on its row. Unticking it keeps the command, its shortcut and
its settings, but nothing can run it until you tick it again.

### The editor

| Field                  | What it does                                                                 |
| ---------------------- | ---------------------------------------------------------------------------- |
| Name                   | What you search for                                                          |
| Command                | The shell command, like `/usr/bin/pmset displaysleepnow`                     |
| Icon                   | A symbol for its row, dialogs and output window                              |
| Arguments              | Values to ask for first, passed as `$1`, `$2` …                              |
| Run In                 | The folder it starts in. Empty means your home folder.                       |
| Load shell environment | Loads your `.zshrc`, so aliases, functions and `PATH` work. Slower to start. |
| Needs confirmation     | Asks before running. **On** by default.                                      |
| Show output            | Opens a window with everything it prints                                     |
| Show confirmation      | Shows a small message when it succeeds                                       |

### How a command runs

|             |                                                     |
| ----------- | --------------------------------------------------- |
| Shell       | `/bin/zsh -lc <command>`                            |
| Folder      | Its Run In folder, or your home folder              |
| Input       | None; anything that asks for input gets end-of-file |
| Environment | Inherited, plus `TINYCAST=1`                        |

**There is no Terminal window and no timeout.** Tinycast never stops a running command on its own,
and a command keeps running if Tinycast quits. The one exception is the **Stop** button in the output
window.

If the Run In folder no longer exists, the command does not run, and Tinycast tells you which folder
is missing. Running it somewhere else would be worse.

### Arguments

A command with arguments asks for each one first, in order, right in the palette. The search field
becomes the input, and the screen lists every argument with what you have answered so far.

- <kbd>return</kbd> moves to the next one. On the last, it runs.
- <kbd>delete</kbd> in an empty field goes back one and brings back what you typed.
- <kbd>esc</kbd> clears your answer, and a second press cancels the run.
- A required argument cannot be left empty.

This works from the launcher, a favorite number, or a global shortcut.

**Values are passed to the shell as `$1`, `$2` …, never pasted into the command text.** A value like
`; rm -rf ~` is just a string your script reads, not a second command. An empty optional argument
still keeps its place, so `$2` never slides into `$3`.

### Load shell environment

This is off by default, and it is the most common reason a command fails.

zsh only reads `~/.zshrc` for **interactive** shells. The default `-lc` reads `.zprofile` and
`.zlogin`, but not `.zshrc`. So your aliases, functions and `PATH` changes are missing, and the
command exits with **127**.

Turning it on uses `-ilc`, which reads `.zshrc`. That also runs everything else your shell startup
does, like oh-my-zsh's auto-update or a theme's background helpers.

`TINYCAST=1` lets your `.zshrc` skip that work:

```bash
[[ -n $TINYCAST ]] && return
```

Measured against a real `.zshrc`: about 10 ms to start with it off, about 65 ms with it on.

When a command exits with 127 and this is off, the error says so and offers **Open Settings…**.

The other fix is to not rely on the shell at all. Use full paths:

```bash
/opt/homebrew/bin/gh pr list --limit 5
```

### Show output

With **Show output** on, a window opens as soon as the command starts and fills in as it prints, in
the right order, with colors.

The window shows the command's name and text, the output, the result and how long it took. **Copy**
is always there. **Stop** ends the command and everything it started; once it finishes, the button
becomes **Run Again**. Progress bars redraw in place instead of printing a line per update.

The window keeps the last 256 KB of output. Scroll up and it stops following new lines; scroll back
to the bottom and it follows again.

With **Load shell environment** on, anything your `.zshrc` prints shows up here too. The
`TINYCAST=1` check above keeps it quiet.

### Needs confirmation

On by default for every command. The palette closes, then a dialog shows the command's **name and
full text**. <kbd>return</kbd> runs it and <kbd>esc</kbd> cancels.

It looks calm rather than alarming. Running a command you wrote deserves a second look, not a red
warning. It cannot be skipped from the palette or from a shortcut, and holding a shortcut down never
stacks up dialogs.

### When it finishes

- **Success, with Show confirmation on:** a small message shows the command's last line of output,
  or "Ran <name>" if it printed nothing.
- **Failure:** a dialog shows the error output, up to the last 8 KB.
- **With Show output on:** the output window reports the result instead, so you never get told twice.

**The command text is never written to logs.**

### Editing and backups

Editing a command keeps its favorite, visibility and shortcut. Deleting it removes all three.

Custom commands and their shortcuts are included in [backups](/docs/reference/backup). Importing
**warns you before it adds commands**, because a backup that quietly adds shell commands would be a
real hazard.

## Importing Raycast script commands

**Settings → Commands → Import Raycast Scripts** reads a folder of
[Raycast script commands](https://github.com/raycast/script-commands) and adds one custom command per
script. It is a one-time import: afterwards they are ordinary commands you can edit or delete.

A file counts as a script command when it has both a shebang line and an `@raycast.title`. Helper
scripts in the same folder are left alone.

| Raycast setting                 | Becomes                                            |
| ------------------------------- | -------------------------------------------------- |
| `@raycast.title`                | The name                                           |
| `@raycast.mode`                 | `compact` and `fullOutput` turn **Show output** on |
| `@raycast.needsConfirmation`    | **Needs confirmation**                             |
| `@raycast.argument1` to `3`     | Arguments, named by their placeholders             |
| `@raycast.currentDirectoryPath` | **Run In**; otherwise the script's own folder      |

Raycast icons are not imported; imported commands use the terminal symbol, and you can pick another.
The import warns you first, and skips any name you already have, so importing the same folder again
only adds new scripts.
