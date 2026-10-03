# Settings file

An opt-in mirror of Tinycast's preferences and all of window management in
`~/.config/tinycast/settings.json`, switched on in **Settings → Backup → Settings File**. `UserDefaults`
stays the store; the file follows it, and an edit made to the file applies at once. The machinery lives
in `Features/Settings/` (`Model/`, `Service/`, `SettingsFileSchema.swift`), and window management's part
in `Features/WindowManagement/`.

## Invariants

- **`UserDefaults` is the store; the file is a mirror.** Every value keeps its `AppSettingsKey` and its
  `didSet`, and the file reads and writes through the same properties. Turning the file on or off,
  deleting it, or updating the app never loses a setting, so there is nothing to migrate.
- **Off by default, and only the pane turns it on.** `settingsFileEnabled` has no key in the file and is
  excluded from backups: a file or an import must never switch on something that reads a file.
- **A capability grant never has a key.** Snippets, Extensions, Calendar access, Auto Join, Camera
  Preview, Quick Actions, MCP and clipboard text recognition are switched on only in the app, which
  asks first. `settings-file-test` checks those paths stay absent.
- **`SettingsFileSchema`'s switch is exhaustive.** A new `SettingsFileKey` case fails to build until it
  is bound to a property.
- **A bad edit never costs a setting.** A key the file leaves out keeps its value; a value Tinycast
  can't use keeps the current one and is reported; an unknown key is reported and ignored; invalid JSON
  applies nothing. An invalid record in a list is skipped and reported, and the rest still apply.
- **Applying the file never writes it.** Only a change made in the app rewrites the file, so hand
  formatting stays until then.
- **Content and machine state never enter it.** Notes, snippets, custom commands, quicklinks, MCP
  servers and AI connections stay where they are — the file can say which folder notes and snippets
  live in, never what is in them — as do the palette's position, the extension toolchain,
  every shortcut outside window management, and what a room learns by being entered.

## Layout

| File | Role |
| --- | --- |
| `Settings/Model/SettingsFileKey.swift` | Every key, in file order; the raw value is its `section.name` path |
| `Settings/Model/SettingsFileJSON.swift` | An ordered JSON tree, so records print in a readable key order |
| `Settings/Model/SettingsFileValue.swift` | Value conversions; `SettingsFileRawValue` and `SettingsFileToken` for enums |
| `Settings/Model/SettingsFileBinding.swift` | One key bound to wherever its value lives |
| `Settings/Model/SettingsFileFormat.swift` | The printer and the parser |
| `Settings/Model/SettingsFileIssue.swift` | Every problem the file can have, and the HUD's line for them |
| `Settings/Model/SettingsFileIdentity.swift` | A stable UUID from a string, for records written without an `id` |
| `Settings/Service/SettingsFileRepository.swift` | The sync: import or replace, save, reload |
| `Settings/Service/SettingsFileMonitor.swift` | Watches the folder and the file, a save-by-rename included |
| `Settings/SettingsFileSchema.swift` | Each key's binding, and the enum conformances |
| `HotKeys/Model/HotKeySpelling.swift` | A binding as typed text |
| `WindowManagement/Model/WindowManagementFileFormat.swift` | Command shortcuts, custom sizes, layouts and rooms as JSON |
| `WindowManagement/Service/WindowManagementSettingsFile.swift` | Their four bindings, shortcuts included |

## Location

`~/.config/tinycast/settings.json` on stable; another channel suffixes the folder, so Dev uses
`tinycast-dev` and a fork its bundle ID. `$XDG_CONFIG_HOME` is not read, because an app opened from
Finder never sees the shell's environment. A symlink is followed and kept: the write lands in its
target, so a file linked from a dotfiles repository stays linked.

## Sync

`AppCore` owns the repository while the switch is on, and nothing while it is off.

- **Turning it on** with no file writes one from the current settings. Over an existing file, a dialog
  asks: **Import** applies the file, **Replace** overwrites it.
- **At launch**, while on, the file is applied last in `start()`, so an edit made while Tinycast was
  quit reaches every sink. A missing file is written again; an unreadable one is reported and left alone.
- **App → file.** Every bound value is read inside `withObservationTracking`; a change saves 300 ms
  later, and the save writes only when the whole render differs from the one the two sides last agreed
  on. Writes are atomic. Quitting or turning the switch off flushes a pending save.
- **File → app.** Two watchers, on the folder and the file, reload 150 ms after the last event. A
  reload skips its own write by comparing bytes. Problems go to a HUD, first one and a count:
  `settings.json: unknown setting “clipboard.enabeld” (+1 more)`.
- **Turning it off** stops both directions and leaves the file on disk.

A side effect of a setting runs from an `AppCore` `track` sink, never from a pane's `.onChange`: the file
can change a setting while no pane is open. Clipboard retention, AI retention and the extensions'
launcher presence are the three that moved for this.

## The format

Sections follow the Settings sidebar and keys the rows of each pane. The app writes strict JSON with two
spaces of indent, every list item on its own line and a trailing newline; comments are not allowed,
because the app rewrites the file.

```json
{
  "general": {
    "showInMenuBar": true,
    "automaticallyCheckForUpdates": true,
    "popToRootSeconds": 0,
    "escapeKeyBehavior": "navigateBackOrClose",
    "autoSwitchInputSource": null,
    "supportReminders": true
  },
  "clipboard": {
    "enabled": true,
    "retentionDays": 90,
    "defaultAction": "paste",
    "disabledApps": [
      "com.apple.keychainaccess",
      "com.apple.Passwords"
    ]
  }
}
```

An enum is its raw value, an unset optional is `null`, and a number with a unit names it in the key.
Where a number has a special case, the case is a word:

| Key | Values |
| --- | --- |
| `clipboard.retentionDays` | 1, 7, 30, 90, 180, 365, `"forever"` |
| `ai.retentionDays` | 7, 30, 90, `"forever"` |
| `ai.newChatAfterMinutes` | 2, 5, 10, 30, `"never"` |
| `ai.toolRounds` | 10, 25, 50, 100, `"unlimited"` |
| `ai.opensTo` | `"recent"`, `"newConversation"` |
| `calendar.launcherLimit` | 1, 3, 5, `"all"` |
| `calendar.span` | `"today"`, `"todayAndTomorrow"`, `"nextSevenDays"` |
| `calendar.menuBar` | `"disabled"`, `"meetingIcon"`, `"meetingTitle"` |
| `calendar.menuBarUpcomingEvents` | `"today"`, or 2, 5, 10, 30 minutes before |
| `calendar.hideCurrentEventAfterMinutes` | `"never"`, 0 (as it starts), 5, 10, 30 |
| `windowManagement.gap` | 0 to 64 |
| `snippets.folder`, `notes.folder` | an absolute or `~/` path, or `null` for Application Support |

## Shortcut chords

`[fn+][ctrl+][option+][shift+][cmd+]key`, written in that order and read in any; `control`, `opt`,
`alt` and `command` also read. While a Hyper key is set, its chord is written `hyper+key`, as the app
shows ✦. The key is the lowercase character this Mac's keyboard types, or a name: `space`, `return`,
`enter`, `tab`, `delete`, `forward-delete`, `escape`, `left`, `right`, `up`, `down`, `home`, `end`,
`page-up`, `page-down`, `help`, `f1`–`f20`, `keypad-0`…; any other key is `key-<code>`. `cmd++` is the
plus key. Keyless bindings are `left|right ctrl|option|shift|cmd`, their `double-tap` forms,
`double-tap ctrl|option|shift|cmd`, `globe` and `double-tap globe`. The
recorder's rule holds: a chord needs ⌘, ⌥, ⌃ or fn unless its key is an F-key.

## Window management

- **`shortcuts`** lists all 35 commands by ID, `null` when unbound; one left out is unbound too.
- **`customSizes`, `layouts` and `rooms`** each carry their record's `shortcut`. A record keeps its `id`,
  because favorites, aliases, ranking and visibility key on it; one written without an `id` gets a
  stable one derived from its name.
- A custom size's `width` and `height` are `"60%"` or `"900pt"`, a bare number read as points. A layout
  app's `width` and `height` are fractions of its display, in full precision.
- A room's window numbers and when it was last entered stay out of the file, and survive an edit to
  the room: `Room.keepingRuntime(of:)` returns a number only to a window of the same app.
- A shortcut the file sets that another action already holds is reported, and the old one stays.

## Adding a setting

1. Add the property to its store as usual, with its `AppSettingsKey` and its
   `SettingsBackupCoverage` entry.
2. Add a `SettingsFileKey` case in pane order, its raw value the `section.name` path.
3. Bind it in `SettingsFileSchema`; an enum conforms to `SettingsFileRawValue`, or to
   `SettingsFileToken` when its file spelling differs from its raw value.
4. Run its side effect from a `track` sink in `AppCore`.

A consent flag, content or machine state gets no key.
