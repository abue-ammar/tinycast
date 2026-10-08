---
title: Commands
description: Every built-in command, and the shell commands you write yourself.
---

Commands are actions you can run by name from the launcher. Some are built in, and you can add your
own shell commands.

## Built-in commands

Each built-in command belongs to one Settings pane. A feature's commands are in that feature's pane
and only appear while the feature is on. The rest are in **Settings → Commands**.

| Pane                                               | Commands                                                                                                                                                                                           |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [AI](/docs/ai)                                     | AI Chat                                                                                                                                                                                            |
| [Quick Actions](/docs/ai/quick-actions)            | Fix Grammar · Rewrite · Translate · Summarize                                                                                                                                                      |
| [Clipboard](/docs/features/clipboard)              | Clipboard History · Paste Sequentially                                                                                                                                                             |
| [Emoji & Symbols](/docs/features/emoji)            | Search Emoji & Symbols                                                                                                                                                                             |
| [File Search](/docs/features/file-search)          | Search Files                                                                                                                                                                                       |
| [Navigation](/docs/features/navigation)            | Switch Windows · Search Menu Bar Items                                                                                                                                                             |
| [Calendar](/docs/features/calendar)                | Join Next Meeting · My Schedule · Create Event · Copy Meeting Link · Open in Calendar                                                                                                              |
| [Notes](/docs/features/notes)                      | Show Notes · Create Note · Search Notes                                                                                                                                                            |
| [Window Management](/docs/features/window-layouts) | Create Window Layout · Create Layout from Current Windows · Switch Room · Create Room                                                                                                              |
| [Quicklinks](/docs/launcher/quicklinks)            | Create Quicklink · Search Quicklinks · Import Quicklinks · Export Quicklinks                                                                                                                       |
| [Snippets](/docs/features/snippets)                | Search Snippets · Create Snippet                                                                                                                                                                   |
| Commands                                           | Calculator History · [Open Camera](/docs/features/camera) · Export Backup · Import Backup · Import from Raycast · Check for Updates · Settings · About Tinycast · Support Tinycast · Quit Tinycast |

Two more commands only appear for what you type: **Open in Browser** and **Run Shell Command**. See
[Fallbacks](/docs/launcher/fallbacks).

Each command's row has a launcher checkbox, a shortcut recorder and an alias field.

You can give any built-in command a global shortcut, with three exceptions. Open in Browser and Run
Shell Command need text to act on, and Quit Tinycast has no shortcut so a stray key press can't quit
the app.

A command that opens a screen works as a toggle: press its shortcut again to close the screen.

**Enable Commands** at the top of Settings → Commands turns off every command in that pane, along
with their shortcuts. Clearing one row's checkbox only hides that command from search; its shortcut
keeps working.

## Custom commands

Give a shell command a name, then run it from search or with its own global shortcut.

Turn custom commands on in **Settings → Commands → Custom Commands**. They're **off** by default.

| Setting                | Default |
| ---------------------- | ------- |
| Enable custom commands | Off     |
| Show in launcher       | On      |

Turning off **Show in launcher** hides the section, but every shortcut keeps working.

Only the command's **name** is searchable, not the command itself, so you can't run something by
half-remembering its flags.

Each command has an **Enabled** checkbox on its row. Clearing it keeps the command, its shortcut and
its settings, but the command can't run until you select the checkbox again.

To take a command out of the main search but keep its shortcut, select it in the launcher and press
<kbd>⇧</kbd><kbd>⌘</kbd><kbd>H</kbd> (**Hide from Root Search**). Turn **Show in root search** back
on in its editor to bring it back.

### The editor

| Field                  | What it does                                                                 |
| ---------------------- | ---------------------------------------------------------------------------- |
| Name                   | What you search for                                                          |
| Command                | The shell command, like `/usr/bin/pmset displaysleepnow`                     |
| Icon                   | A symbol for its row, dialogs and output window                              |
| Show in root search    | Lists it in the main search. Off, only its shortcut runs it.                 |
| Arguments              | Values to ask for first, passed as `$1`, `$2` …                              |
| Run In                 | The folder it starts in. Empty means your home folder.                       |
| Load shell environment | Loads your `.zshrc`, so aliases, functions and `PATH` work. Slower to start. |
| Needs confirmation     | Asks before running. **On** by default.                                      |
| Show output            | Opens a window with everything the command prints                            |
| Show confirmation      | Shows a short message when the command succeeds                              |

### How a command runs

|             |                                                     |
| ----------- | --------------------------------------------------- |
| Shell       | `/bin/zsh -lc <command>`                            |
| Folder      | Its Run In folder, or your home folder              |
| Input       | None; anything that reads input gets an end-of-file |
| Environment | Inherited, plus `TINYCAST=1`                        |

**Commands run without a Terminal window and without a timeout.** Tinycast never stops a running
command by itself, and a command keeps running if Tinycast quits. The only way to stop one is the
**Stop** button in the output window.

If the Run In folder no longer exists, the command doesn't run, and Tinycast tells you which folder
is missing instead of running it somewhere else.

### Arguments

A command with arguments asks for each one in order, in the palette, before it runs. The search field
becomes the input, and the screen lists every argument with the answers you've given so far.

- <kbd>return</kbd> moves to the next argument. On the last one, it runs the command.
- <kbd>delete</kbd> in an empty field goes back to the previous argument and restores what you typed.
- <kbd>esc</kbd> clears your answer, and a second press cancels the run.
- A required argument can't be left empty.

This works whether you run the command from the launcher, a favorite number or a global shortcut.

**Values are passed to the shell as `$1`, `$2` …, and are never inserted into the command text.** A
value like `; rm -rf ~` is only a string your script reads, not a second command. An empty optional
argument still keeps its position, so `$2` never shifts into `$3`.

### Load shell environment

This setting is off by default, and it's the most common reason a command fails.

zsh only reads `~/.zshrc` for **interactive** shells. The default `-lc` reads `.zprofile` and
`.zlogin`, but not `.zshrc`. As a result, your aliases, functions and `PATH` changes are missing, and
the command exits with code **127**.

Turning the setting on uses `-ilc`, which reads `.zshrc`. That also runs everything else in your
shell startup, like oh-my-zsh's auto-update or a theme's background helpers.

Tinycast sets `TINYCAST=1`, so your `.zshrc` can skip that work:

```bash
[[ -n $TINYCAST ]] && return
```

With a typical `.zshrc`, a command starts in about 10 ms with the setting off and about 65 ms with it
on.

When a command exits with 127 while this setting is off, the error message says so and offers
**Open Settings…**.

You can also avoid relying on the shell configuration by using full paths:

```bash
/opt/homebrew/bin/gh pr list --limit 5
```

### Show output

With **Show output** on, a window opens as soon as the command starts and shows its output as it's
printed, in order and in color.

The window shows the command's name and text, the output, the result and how long it took. **Copy**
is always available. **Stop** ends the command and everything it started; when the command finishes,
the button changes to **Run Again**. Progress bars update in place instead of printing a new line for
each update.

The window keeps the last 256 KB of output. If you scroll up, it stops following new output. Scroll
back to the bottom and it follows again.

With **Load shell environment** on, anything your `.zshrc` prints also appears here. The
`TINYCAST=1` check above keeps it quiet.

### Needs confirmation

This is on by default for every command. The palette closes, and a dialog shows the command's
**name and full text**. <kbd>return</kbd> runs it and <kbd>esc</kbd> cancels.

The dialog is a plain confirmation rather than a red warning, since you wrote the command yourself.
You can't skip it from the palette or a shortcut, and holding down a shortcut never opens more than
one dialog.

### When it finishes

- **Success, with Show confirmation on:** a short message shows the last line of output, or
  "Ran <name>" if the command printed nothing.
- **Failure:** a dialog shows the error output, up to the last 8 KB.
- **With Show output on:** the output window shows the result instead, so you're only told once.

**Tinycast never writes the command text to its logs.**

### Editing and backups

Editing a command keeps its favorite, visibility and shortcut. Deleting it removes all three.

Custom commands and their shortcuts are included in [backups](/docs/reference/backup). When you
import a backup, Tinycast **warns you before adding any commands**, so a backup can't add shell
commands without you knowing.

## Importing Raycast script commands

**Settings → Commands → Import Raycast Scripts** reads a folder of
[Raycast script commands](https://github.com/raycast/script-commands) and adds a custom command for
each script. It's a one-time import: afterward they're regular commands you can edit or delete.

A file counts as a script command when it has both a shebang line and an `@raycast.title`. Other
helper scripts in the folder are skipped.

| Raycast setting                 | Becomes                                            |
| ------------------------------- | -------------------------------------------------- |
| `@raycast.title`                | The name                                           |
| `@raycast.mode`                 | `compact` and `fullOutput` turn **Show output** on |
| `@raycast.needsConfirmation`    | **Needs confirmation**                             |
| `@raycast.argument1` to `3`     | Arguments, named after their placeholders          |
| `@raycast.currentDirectoryPath` | **Run In**; otherwise the script's own folder      |

Raycast icons aren't imported. Imported commands use the terminal symbol, and you can choose a
different one. Tinycast warns you before importing and skips any name you already have, so importing
the same folder again only adds new scripts.
