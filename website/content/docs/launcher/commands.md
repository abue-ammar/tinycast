---
title: Commands
description: The built-in command catalog, and your own shell commands.
---

The **Commands** pane holds two separate things: Tinycast's built-in commands, and custom shell
commands you write.

## Built-in commands

These are Tinycast's own screens and operations, reachable by name from the launcher:

Calculator History · Clipboard History · Search Emoji & Symbols · Search Files · Open Camera ·
Show Notes · Create Note · Search Notes · Create Quicklink · Search Quicklinks · Import Quicklinks ·
Export Quicklinks · Export Backup · Import Backup · Import from Raycast · Settings ·
About Tinycast · Quit Tinycast

Seven of them also carry their own global shortcut: Search Files, Clipboard History,
Search Emoji & Symbols, Open Camera, Show Notes, Create Note and Search Notes.

Each row in **Settings → Commands** has a visibility checkbox, a shortcut recorder and an alias
field. A command belonging to a disabled feature does nothing until you enable that feature.

## Custom commands

Name a shell command and run it from search or its own global hotkey.

**Settings → Commands → Custom Commands** holds the feature switch. It ships **off**.

| Setting                | Default |
| ---------------------- | ------- |
| Enable custom commands | Off     |
| Show in launcher       | On      |

Turning **Show in launcher** off hides the section but keeps every shortcut working.

Only the **name** you give a command is searchable. The command text deliberately is not — you
should not be able to summon something by half-remembering its flags.

### How a command runs

|                   |                                                   |
| ----------------- | ------------------------------------------------- |
| Shell             | `/bin/zsh -lc <command>`                          |
| Working directory | Your home folder                                  |
| stdin / stdout    | `/dev/null`                                       |
| Environment       | Inherited, plus `TINYCAST=1`                      |
| Errors            | Up to 8 KiB of stderr kept for the failure dialog |

**There is no Terminal window and no timeout.** Tinycast never kills a running command, and a
command outlives Tinycast quitting. Interactive prompts cannot block it — a `read` gets EOF and
`/dev/tty` fails.

### Load shell environment

This per-command toggle is off by default, and it is the single most common reason a command fails.

zsh only reads `~/.zshrc` for **interactive** shells. The default `-lc` sees `.zprofile` and
`.zlogin` but not `.zshrc` — so your aliases, functions and `PATH` edits are all missing, and the
command exits **127**.

Turning the toggle on switches to `-ilc`, which sources `.zshrc`. That also runs everything else your
shell startup does: oh-my-zsh's auto-update, powerlevel10k's `gitstatusd`, `compinit`, or an `exec`
that replaces the shell entirely.

`TINYCAST=1` exists so your rc file can skip that work:

```bash
[[ -n $TINYCAST ]] && return
```

Cost, measured against a real `~/.zshrc`: about 10 ms for `-lc`, about 65 ms for `-ilc`.

When a command exits 127 with the toggle off, the failure dialog says so directly and offers an
**Open Settings…** button that lands on this pane.

The other fix is to not depend on the shell at all — use full paths:

```bash
/opt/homebrew/bin/gh pr list --limit 5
```

### Needs confirmation

Per command, and on by default for good reason. The palette hides, then a dialog shows the command's
**name and its full text**. <kbd>↵</kbd> runs it, <kbd>⎋</kbd> cancels, Cancel sits on the left.

It reads neutral rather than alarming — running a command you wrote yourself deserves a deliberate
second tap, not a red warning. The gate cannot be bypassed from the palette or from a hotkey.

### Failures

Exit status zero is silent. A launch failure or a non-zero status opens a dialog with the bounded
error output.

**The command text itself is never logged.**

### Editing

Editing a command keeps its favorite, visibility and hotkey. Deleting it clears all three.

Custom commands and their bindings are included in
[settings backups](/docs/reference/backup) — and import **warns you before accepting executable
content**, because a backup file that silently adds shell commands would be a genuine hazard.
