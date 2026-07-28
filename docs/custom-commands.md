# Custom commands

Custom commands let users add a searchable name and a shell command in **Settings → Custom
Commands**. They appear in the launcher's Commands section, share the normal fuzzy ranking, and run
from Return, a favorite slot, or an optional global shortcut.

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
entries supplied on the main actor. It publishes those followed by one alphabetized command slice
containing both `CommandRegistry` and user commands. This keeps the visible row order identical to
the flat palette selection while allowing edits to invalidate fuzzy results without rescanning disk.

The command text is deliberately not searchable. Only the user-facing name enters fuzzy matching.

## Execution contract

`ShellCommandRunner` executes asynchronously with:

- `/bin/zsh -lc <command>`
- the user's home directory as the working directory
- standard input and output connected to `/dev/null`
- up to 8 KiB of standard error retained for a failure alert

No Terminal window or pseudo-terminal is created. Interactive prompts and `sudo` therefore fail
rather than blocking for input. A command should use full executable paths when it depends on tools
that may not be configured in a login shell.

Tinycast dismisses an open palette before starting a custom command. A zero exit status is silent; a
launch failure or non-zero status activates Tinycast and shows the bounded error detail. The command
string itself is never logged.
