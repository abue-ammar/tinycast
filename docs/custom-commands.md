# Custom commands

Custom commands let users add a searchable name and a shell command in **Settings → Custom
Commands**. They appear in the launcher's Custom Commands section, share the normal fuzzy ranking,
and run from Return, a favorite slot, or an optional global shortcut.

The pane carries the feature switch — off out of the box — and its launcher-visibility companion,
both in `AppSettings` and in settings backups. Switching the feature off empties the launcher section and makes
`AppCore.runCustomCommand` — the single funnel for palette activation and global shortcuts — refuse to
run anything; Carbon registrations and their bindings stay put, so re-enabling restores every shortcut
without re-registering. "Show in launcher" only hides the section; shortcuts keep working.

## Ownership and persistence

`CustomCommandStore` is owned by `AppCore` and persists the ordered command array as JSON in
bundle-scoped `UserDefaults`. Each command has a stable UUID. Its launcher entry id is
`custom-command:<uuid>`, and its hotkey uses
`KeyboardShortcuts_customCommandHotkey.<uuid>` plus the `boundCustomCommandIDs` index.

Editing preserves the UUID and therefore its favorite, visibility, and hotkey references. Deleting
goes through `AppCore`, which unregisters the hotkey and clears those references before removing the
command. Native settings backups include both commands and bindings; import warns before accepting
executable content.

## Launcher integration

`AppIndex` owns two slices: applications/System Settings discovered off-main and custom command
entries supplied on the main actor. It publishes the custom command slice ahead of the alphabetized
`CommandRegistry` built-ins, each its own launcher section. This keeps the visible row order identical
to the flat palette selection while allowing edits to invalidate fuzzy results without rescanning disk.

The command text is deliberately not searchable. Only the user-facing name enters fuzzy matching.

## Execution contract

`ShellCommandRunner` executes asynchronously with:

- `/bin/zsh -lc <command>`, or `/bin/zsh -ilc <command>` when the command's **Load shell
  environment** flag is on
- the user's home directory as the working directory
- standard input and output connected to `/dev/null`
- `TINYCAST=1` added to the inherited environment
- up to 8 KiB of standard error retained for a failure alert

No Terminal window or pseudo-terminal is created. `waitUntilExit` blocks for the whole life of the
command, so it runs on a private concurrent `DispatchQueue` rather than a cooperative-pool thread a
long `brew upgrade` would hold for minutes.

### Load shell environment

zsh reads `~/.zshrc` **only for interactive shells**, so the default `-lc` sees `.zprofile` and
`.zlogin` and nothing else — a user's aliases, functions and `PATH` edits are all absent, and the
command exits **127**. That is the single most common way a custom command fails. The flag switches to
`-ilc`, which sources the rc file.

It is per-command and off by default, because turning it on runs whatever the user's shell startup
does — oh-my-zsh's auto-update (`git pull`, network, seconds), powerlevel10k's `gitstatusd`,
`compinit` rewriting `~/.zcompdump`, or an `exec` that replaces the shell so the command never runs at
all. `TINYCAST=1` exists so an rc file can skip those sections: `[[ -n $TINYCAST ]] && return`.

Measured cost: ~10 ms for `-lc`, ~65 ms for `-ilc` against a real-world `~/.zshrc` (~11 ms against a
minimal one — the interactive shell itself is ~2 ms, the rest is the user's own config).

Interactive prompts still cannot block. Standard input is `/dev/null`, so a `read` gets EOF and
returns non-zero, and a launchd-launched app has no controlling terminal, so `/dev/tty` fails with
`device not configured`. A dev build launched *from a terminal* inherits that terminal's tty, so an rc
file reading `/dev/tty` can hang there but not for real users. There is **no timeout** — Tinycast
never kills a running command, and a command outlives Tinycast quitting.

Because standard error surfaces only on a non-zero exit and only its last 8 KiB, rc-file startup noise
is dropped while the actual error survives.

### Needs confirmation

`AppCore.runCustomCommand(id:)` is the one funnel both palette activation and the global hotkey reach,
so the gate lives there and neither path can bypass it. The palette hides before the alert — it is a
floating panel and would sit above it. The alert shows the command text as well as its name, and ↵ is
bound to **Cancel**: the command is one ↵ away in the palette, and a reflexive second ↵ must not fire
something the user asked to be warned about. `NSAlert.runModal` spins a nested run loop where Carbon
hotkeys keep firing, so a re-entrancy flag stops a held shortcut stacking alerts.

### Reporting

Tinycast dismisses an open palette before starting a custom command. A zero exit status is silent; a
launch failure or non-zero status activates Tinycast and shows the bounded error detail. When the
status is 127 and **Load shell environment** is off, the alert adds a one-line hint and an **Open
Settings…** button that lands on the Custom Commands pane — the hint is gated on the status alone, not
on grepping stderr, since 127 is equally a plain typo. The command string itself is never logged.

### Manual checks

`requiresConfirmation` lives in `AppCore` (AppKit, `@MainActor`) and so is out of reach of the
Foundation-only harness. Verify by hand:

1. Activating a gated command from the palette hides the palette *before* the alert appears.
2. ↵ at the alert cancels; clicking **Run** runs.
3. Pressing the command's hotkey while its alert is up does not stack a second alert.
4. A gated command triggered by hotkey with no palette open still confirms.
5. An rc-file-only alias with the flag off shows the 127 hint, and **Open Settings…** opens the pane.
