# Custom commands

Custom commands let users add a searchable name and a shell command in **Settings → Custom
Commands**. They appear in the launcher's Custom Commands section, share the normal fuzzy ranking,
and run from Return, a favorite slot, or an optional global shortcut. A command may declare
[arguments](#arguments) it is asked for first, and may [show what it printed](#show-output) when it
finishes.

The pane carries the feature switch — off out of the box — and its launcher-visibility companion,
both in `AppSettings` and in settings backups. Switching the feature off empties the launcher section and makes
`CustomCommandCoordinator.runCustomCommand` — the single funnel for palette activation and global shortcuts — refuse to
run anything; Carbon registrations and their bindings stay put, so re-enabling restores every shortcut
without re-registering. "Show in launcher" only hides the section; shortcuts keep working.

## Invariants

- **`Model/CustomCommand.swift`, `Service/ShellCommandRunner.swift` and
  `Service/CustomCommandArgumentSession.swift` stay free of AppKit and SwiftUI** (Foundation plus Darwin
  for `mkstemp`) so `custom-command-test` can compile them standalone. That is why the confirmation gate
  lives in `CustomCommandCoordinator` and not in the runner.
- A command that runs arbitrary shell is a security surface: the confirmation step cannot be bypassed, and
  an import of executable commands warns before it applies.
- **An argument value is never spliced into the command text.** It is handed to zsh as a positional
  parameter, so a value carrying `;`, backticks or `$(…)` is data the script reads, never syntax the
  shell runs. `custom-command-test` asserts this directly.

## Ownership and persistence

`CustomCommandStore` is owned by `AppCore` and persists the ordered command array as JSON in
bundle-scoped `UserDefaults`. Each command has a stable UUID. Its launcher entry id is
`custom-command:<uuid>`, and its hotkey uses
`hotkey.customCommand.<uuid>` plus the `boundCustomCommandIDs` index.

Editing preserves the UUID and therefore its favorite, visibility, and hotkey references. Deleting
goes through `AppCore`, which unregisters the hotkey and clears those references before removing the
command. Native settings backups include both commands and bindings; import warns before accepting
executable content.

## Launcher integration

`AppIndex` owns two slices: applications/System Settings discovered off-main and custom command
entries supplied on the main actor. It publishes the custom command slice ahead of the alphabetized
`CommandCatalog` built-ins, each its own launcher section. This keeps the visible row order identical
to the flat palette selection while allowing edits to invalidate fuzzy results without rescanning disk.

The command text is deliberately not searchable. Only the user-facing name enters fuzzy matching.

## Execution contract

`ShellCommandRunner` executes asynchronously with:

- `/bin/zsh -lc <command>`, or `/bin/zsh -ilc <command>` when the command's **Load shell
  environment** flag is on
- `tinycast` as `$0`, then the collected argument values as `$1`, `$2`, …
- the user's home directory as the working directory
- standard input reading EOF immediately
- `TINYCAST=1` added to the inherited environment
- up to 8 KiB of standard error retained for a failure dialog
- standard output discarded

**Show output** takes a different route entirely — see [Show output](#show-output). Nothing else does.

No Terminal window or pseudo-terminal is created. `waitUntilExit` blocks for the whole life of the
command, so it runs on a private concurrent `DispatchQueue` rather than a cooperative-pool thread a
long `brew upgrade` would hold for minutes. The streaming path blocks the same queue on `read`.

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

Interactive prompts still cannot block. Standard input is `/dev/null` — or, under **Show output**, a
pty already sent EOF — so a `read` gets EOF and
returns non-zero, and a launchd-launched app has no controlling terminal, so `/dev/tty` fails with
`device not configured`. A dev build launched _from a terminal_ inherits that terminal's tty, so an rc
file reading `/dev/tty` can hang there but not for real users. There is **no timeout** — Tinycast never kills a
running command except through the output window's Stop button, and a command outlives Tinycast
quitting.

Because standard error surfaces only on a non-zero exit and only its last 8 KiB, rc-file startup noise
is dropped while the actual error survives.

### Arguments

A command may declare an ordered list of arguments, each a name and an optional/required flag. Running
one opens `PaletteMode.customCommandArguments` — the same shape as the quicklink argument prompt: the
palette's own search field _is_ the input, one argument at a time, with the field's placeholder naming
the pending one and the body listing every argument, its `$n` slot, and what has been answered. ↵
advances, a bare backspace steps back and refills the field, and Escape abandons the run. `↵` is held
while a required argument is empty, which also hides the footer pill.

Because the form is a palette mode rather than a header accessory, **every entry point gets it** —
launcher row, favorite slot and global hotkey alike — through the one `runCustomCommand(id:)` funnel.
That is the whole reason it is not an inline strip beside the search field the way an extension
command's arguments are: a hotkey has no selected row to hang one off.

Values reach zsh as **positional parameters**, never as text substituted into the command:

```
/bin/zsh -lc '<command>' tinycast <value1> <value2> …
```

so the script reads them as `$1`, `$2`, and a value containing `; rm -rf ~` is a string, not a second
command. An optional argument submitted empty still occupies its slot, so `$2` never becomes `$3`.
`CustomCommandArgumentSession` owns the pending run; it holds values positionally for the same reason,
which is why two arguments may share a name without colliding.

### Show output

Off by default. With it on the run goes through `ShellCommandRunner.stream` and a
`PseudoTerminal` instead of `run` and a pipe, the window opens **before the first byte**, and the log
fills in as the command prints it.

#### Why a pty and not a pipe

A pipe cannot deliver either half of what this promises, and both failures were measured rather than
assumed:

- **Nothing is live.** libc switches stdout from line-buffered to fully buffered the moment it is not
  a terminal. A command printing a line every 0.4 s delivered all four lines within 20 ms of each
  other, at exit.
- **The order is wrong.** stderr stays unbuffered while stdout does not, so stderr overtakes the
  stdout it followed. `print` / `write(stderr)` / `print` came out as 2, 1, 3 — through a *single
  merged pipe*. Merging is not enough; only a terminal restores line buffering, and with it the
  order. Under a pty the same command printed 1, 2, 3.

`PseudoTerminal` also spawns with `POSIX_SPAWN_SETSID`, which is what makes Stop honest: the command
leads its own session, so one `kill(-pid)` reaches the whole `a && b && c` chain. `Process.terminate`
signals only zsh — a `sleep` started behind it survives, verified.

The pty's stdin gets an EOT byte at spawn, which keeps the invariant a `/dev/null` stdin gave the
pipe path: a command that prompts reads EOF and moves on rather than waiting on a terminal that will
never answer.

#### What the window shows

One flat surface, no rules. The command's name, the shell text under it (`brew` alone says nothing
about what ran), the log, and a footer with a status dot, the outcome and the elapsed time. Copy is
always there; the second control is **Stop** while it runs and **Run Again** once it has.

Because a terminal makes tools colour their output, `ANSIInterpreter` renders SGR colour rather than
printing the escapes — that is what replaces the old red-stderr tint, which was a mistake: stderr is
where most tools log progress, so colouring it as an error made a successful `brew update` look
broken. A bare carriage return rewinds its line, so a progress bar redraws in place instead of
stacking a line per frame.

The log is an `NSTextView` and only the undrawn tail is appended; a quarter-megabyte of output
re-laid-out per line is seconds of work. The run publishes each append as an explicit `delta` and
`revision`, so the view adds just that when it is exactly one step behind and redraws from the whole
log otherwise — a new run, a trim, or a window reopened onto a finished one. Past 256 KiB the head is dropped. Following the tail stops
when the reader scrolls up and resumes when they reach the bottom, the same band the chat transcript
uses.

**The window replaces the failure dialog rather than joining it**, so a run is never reported twice;
the success pill is skipped for the same reason.

#### Consequences worth knowing

- **rc-file noise is now visible.** With **Load shell environment** on, anything `~/.zshrc` writes
  reaches the log. The guard is the documented `[[ -n $TINYCAST ]] && return`.
- **Stop is the one exception** to "Tinycast never kills a running command". Only the button does it;
  a second command superseding the window never touches the first.

### Needs confirmation

`CustomCommandCoordinator.runCustomCommand(id:)` is the one funnel both palette activation and the global hotkey reach,
so the gate lives there and neither path can bypass it. The palette hides before the dialog it is a
floating panel and would sit above it. The dialog shows the command text as well as its name; ↵ runs
it and Escape cancels, with Cancel rendered on the left of the two buttons. It carries the `terminal`
glyph the command's launcher row uses, and reads neutral rather than destructive — running a command the
user wrote themselves wants a deliberate second tap, not a red alarm. The gate is Tinycast's own
dialog, not an `NSAlert` ([ui.md](../ui.md#dialogs--hud)): presentation is `async` with no nested run loop,
and the presenter itself refuses a second dialog while one is up, so a held shortcut can't stack them.

### Reporting

Tinycast dismisses an open palette before starting a custom command. With **Show output** off, a zero
exit status is silent; a launch failure or non-zero status opens a Tinycast dialog with the bounded
error detail. When the
status is 127 and **Load shell environment** is off, the dialog adds a one-line hint and an **Open
Settings…** button that lands on the Commands pane — the hint is gated on the status alone, not
on grepping stderr, since 127 is equally a plain typo. The command string itself is never logged.

### Manual checks

`requiresConfirmation` lives in `AppCore` (AppKit, `@MainActor`) and so is out of reach of the
Foundation-only harness. Verify by hand:

1. Activating a gated command from the palette hides the palette _before_ the dialog appears.
2. ↵ at the dialog runs the command; Escape or clicking **Cancel** cancels.
3. Pressing the command's hotkey while its dialog is up does not stack a second dialog.
4. A gated command triggered by hotkey with no palette open still confirms.
5. An rc-file-only alias with the flag off shows the 127 hint, and **Open Settings…** opens the pane.
6. A command with arguments triggered by hotkey opens the argument form, not the command.
7. A gated command with arguments asks for every value first, and confirms only once.
8. Running a second output-showing command reuses the one window and does **not** kill the first.
9. A long command's output appears while it runs, not at the end; scrolling up stops the follow.
10. Stop during `brew update` leaves nothing behind — check with `pgrep -f brew`.
11. Clicking the Dock icon while a command runs raises the output window, not the launcher.
12. **Run Again clears the log before the new run prints.** The view draws deltas, so it keys what
    it has drawn on the run's id as well as the trim counter — a fresh run starts back at revision
    zero, and keying on the counter alone left the previous run's output on screen.
