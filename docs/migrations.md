# Migrations

A migration repairs state that an older release left behind, such as a retired key in
`settings.json` or an orphaned default. It ships in exactly one stable release and is then deleted,
so the codebase never carries a history of its past formats.

## Invariants

- **Every migration lives in `Tinycast/Migrations/`**, one file and one `<Subject>Migration` type
  each. Its call sites name that type, so deleting the file fails the build at every one of them.
- **One stable release, then gone.** `Scripts/check-migrations.sh` fails `lint.sh` and the Release
  workflow once a stable tag (`vX.Y.Z`) contains the commit that added the file. Beta tags do not
  count: the beta channel runs it on the way to that stable release.
- **Missing it must be harmless.** A user who skips that release never runs it, so a migration only
  tidies. A value a later release depends on is never left to one.
- **Except a dated row.** When no later release can work without the migration, its row names a
  `YYYY-MM-DD` instead, and the check fails from that day rather than at the first stable tag. The
  bundle id move is the one case: without it a copy opens empty, its data still under the old id.
- **Idempotent and silent.** It runs on every launch of its release, does nothing when there is
  nothing to repair, and reports nothing.
- **Every live migration has a row below.** The check fails for a file the table does not name.

## Adding one

Write the type in `Migrations/` and call it from `AppCore.start()` before anything reads the state it
repairs, or from `TinycastLaunch.main` when that state is read before `AppCore` exists. Cover it
with a harness of its own, so deleting it removes a whole file, one `run-tests.sh` entry and one row
in [testing.md](testing.md). Then add its row here.

## Deleting one

When the check fails, delete everything the row lists, then the row. Then run `xcodegen generate`,
`./Scripts/run-tests.sh` and `./Scripts/lint.sh`.

## Live migrations

| Migration | Repairs | Delete with it |
| --- | --- | --- |
| `BundleIdentifierMigration` | Moves `com.tinycast.app[.beta\|.dev]`'s preferences, Application Support and Caches folders, clipboard image paths, the snippet paths its preferences and JSON files key records by, and login item to `com.abueammar.tinycast[.beta\|.dev]`. Keychain secrets stay behind: moving them asks once per item, so users enter them again. Kept until **2027-05-13** | Everything in [Removing the bundle id move](#removing-the-bundle-id-move) |

### Removing the bundle id move

The migration and the handoff release are one piece, and go together. Afterwards, searching the repo
for `Handoff`, `LEGACY`, `BundleIdentifierMigration` and `com.tinycast.app` finds nothing.

**Delete these files**

- `Tinycast/Migrations/BundleIdentifierMigration.swift`
- `Tinycast/Migrations/Handoff/`, the whole folder: `BundleIdentifierHandoff.swift` and `Info.plist`
- `Tests/BundleIdentifierMigrationTests.swift`
- `Scripts/wrap-handoff.sh`
- `Scripts/package-handoff.sh`

**Remove these lines**

- `Tinycast/App/TinycastApp.swift`: the `BundleIdentifierMigration.run()` call in
  `TinycastLaunch.main`.
- `Tinycast/Features/Updates/Model/ReleaseFeed.swift`: `handoffMarker` and its doc comment, and its
  check in `asset(from:for:)`, so the filter is `$0.name.hasSuffix(".zip")` again.
- `Tests/UpdatesTests.swift`: the `com.tinycast.app` expectation in `derivesChannels`, and the
  `handoff` and `handoffOnly` cases at the end of `picksTheZipThisMacCanRun`.
- `Scripts/run-tests.sh`: the `run BundleIdentifierMigrationTests` entry.
- `Scripts/check-migrations.sh`: the dated-row block: its comment, the `until=` line and the
  `if [ -n "$until" ]` block around `continue`.
- `project.yml`: both `TINYCAST_LEGACY_BUNDLE_IDENTIFIER` settings, the `Migrations/Handoff` exclude
  in the `Tinycast` target, and the whole `TinycastHandoff` target with its comment. Then run
  `xcodegen generate`, so `Tinycast.xcodeproj` loses them too.
- `.github/workflows/release.yml`:
  - the `legacy_bundle_id` job output;
  - in "Compute release metadata", the `LEGACY=` line with its comment, and the `legacy_bundle_id`
    and `handoff_file` echoes;
  - both "Build and notarize the handoff" steps, and the comment above the build job's one;
  - in "Publish GitHub Release", the handoff files in `gh release create`: give it the DMG, the zip
    and the `.sig` again, and delete the second `gh release upload` call with its comment;
  - in the `universal` job, the `LEGACY_BUNDLE_ID` env, and the first `gh release upload` call (the
    handoff) with the comment after it.

**Edit these docs**

- [testing.md](testing.md): the `BundleIdentifierMigrationTests` row.
- [release.md](release.md): the whole "The bundle id handoff" section.
- [features/updates.md](features/updates.md): the paragraph under the channel table that starts
  "Until 2027-05-13".
- This file: the "Except a dated row" invariant, the "or from `TinycastLaunch.main`" clause in
  [Adding one](#adding-one), the `BundleIdentifierMigration` row and this section.

**Left on users' Macs, with no code to remove it:** an empty `com.tinycast.app*.plist`, Keychain
secrets under the old names, stale permission entries in System Settings, and a `Migration Backup`
folder for anyone migrated in the last 30 days.
