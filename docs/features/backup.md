# Backup

Export and import of Tinycast's own settings, plus the entry point for importing a Raycast export. The
feature lives in `Features/Backup/`.

## Invariants

- **`SettingsBackup`'s mirror is hand-written, and reflection is never the fix.** `AppSettingsKey` owns
  every key `AppSettings` persists; `SettingsBackupCoverage` says which of them `SettingsData` carries,
  which are sourced from somewhere other than `UserDefaults`, and which are excluded **with a reason**.
  `settings-backup-test` fails when a key is none of those. Adding a setting means editing
  `SettingsBackupCoverage` in the same commit.
- **`snippetsEnabled` is excluded, and that is a security control.** It doubles as consent to keystroke
  listening, so an imported file must not be able to grant it. A `Mirror` or a macro is the wrong
  answer: neither can be read to check what is covered.
- **A flag that grants a capability is never carried by a backup**, whether it is excluded from
  `SettingsBackupCoverage` like `snippetsEnabled` or kept out of `AppSettings` entirely. Importing a
  config must not be able to grant something the user never granted.
- The format is internal and may change freely. The only requirement is that **export → import
  round-trips within one build** — there is no version field and no migration.

## Layout

| File | Role |
| --- | --- |
| `Model/SettingsBackup.swift` | The `SettingsData` payload and its `Codable` shape |
| `Model/SettingsBackupCoverage.swift` | The coverage declaration the harness checks |
| `Model/RaycastFormat.swift` | Detects v1 vs v2 — the only branch between the two |
| `Model/RaycastV1Decoder.swift` | v1 decrypt and decode |
| `Model/RaycastImportV1.swift` | v1 → Tinycast field mapping and validation |
| `Model/RaycastImport.swift` | The shared `Result` both formats meet at |
| `Service/RaycastImportV2.swift` | v2 decrypt, decode and mapping |
| `Service/Scrypt.swift`, `Service/Gunzip.swift` | The crypto and decompression primitives |
| `Service/BackupActions.swift` | The effectful half: file pickers, writes, applying an import |
| `Settings/BackupSettingsView.swift` | The pane |

## Coverage, and why it is spelled out

`SettingsBackupCoverage` holds three tables:

- `mirrored` — each `SettingsData` field paired with the `AppSettings` key it carries.
- `externallySourced` — fields no `AppSettings` key stands behind, each saying what it reads instead.
  `launchAtLogin` comes from `LaunchAtLogin`, which owns the login item; `showInMenuBar` is shared with
  `MenuBarExtra` via `SettingsKey` rather than owned here.
- `deliberatelyExcluded` — keys kept out on purpose, each with its reason as a string.

`settings-backup-test` asserts that every `AppSettingsKey` appears in exactly one table, that no field
claims a key twice, that every exclusion names a real key and carries a non-empty reason, and
specifically that `snippetsEnabled` is absent from a produced backup. The duplication between
`AppSettings` and this file is the point: it forces a decision about every new setting rather than
defaulting it into a backup.

## Importing

Applying an import writes through `AppSettings` like any other change, so feature switches reproject into
the launcher through the normal observation path. An import reports a summary of what it applied — it is
not silent, because a settings file that quietly changes hotkeys is hostile.

Raycast import is documented separately in [raycast-import.md](raycast-import.md); the two formats share
no mapper, which is what makes a wrong passphrase report a wrong passphrase.
