# Native extensions: status

Last updated 2026-11-28. The design is [native-extensions-plan.md](native-extensions-plan.md); this
file records what is done, what was decided on the way, and what comes next.

## Phases

| Phase | What                                   | Repo                   | State            | Branch / PR                 | Date       |
| ----- | -------------------------------------- | ---------------------- | ---------------- | --------------------------- | ---------- |
| 0     | Remove Raycast extensions              | app                    | Done, not merged | `ext/0-remove-raycast`      | 2026-11-28 |
| 1     | The contract                           | extensions             | Done             | `main`                      | 2026-11-28 |
| 2     | SDK, CLI and a first extension         | extensions             | Not started      |                             |            |
| 3     | The host                               | app                    | Not started      | `ext/3-host`                |            |
| 4     | Host-drawn UI                          | app                    | Not started      | `ext/4-ui`                  |            |
| 5     | Permissions                            | app                    | Not started      | `ext/5-permissions`         |            |
| 6     | Menu bar and background refresh        | app                    | Not started      | `ext/6-menu-bar-background` |            |
| 7     | Publishing pipeline and install counts | extensions, Cloudflare | Not started      |                             |            |
| 8     | Installer, updates and Store           | app                    | Not started      | `ext/8-installer-store`     |            |
| 9     | Docs, skills and launch                | both                   | Not started      | `ext/9-docs`                |            |

App step branches come off `native-extensions` and merge back into it. The extensions repo commits
to its own `main`.

## Log

### 2026-11-28 · Phase 1: the contract

`tinycast-extensions` holds the SDK package and the one definition of everything the app and an
extension both read. `swift build` and `swift test` pass with warnings as errors, and the schema
check passes.

**Built**

- The repo: `Package.swift` (tools 6.2, Swift 6, macOS 26, no dependencies), MIT `LICENSE`,
  `CODEOWNERS`, both AGENTS.md files, the app's `.swift-format` and a VS Code launch config.
  `TinycastKit` and `TinycastCLI` are empty targets until Phase 2.
- `TinycastProtocol` v1: the seven messages, the List, Grid, Detail, Form and MenuBar trees, the
  host calls and their errors, the manifest with its validation, the permissions, the Store index
  and `ExtensionAPIVersion`.
- `schema/extension.schema.json` (JSON Schema 2020-12) and `Scripts/check-schema.sh`, which runs
  ajv through `npx` over the same fixtures the Swift tests read.
- Tests: one JSON fixture per message variant, checked by decoding and by comparing the encoded
  JSON; the plan's sample manifest; one counter-example per manifest rule; the plan's index sample.
- `ci.yml` builds, tests and checks the schema on every PR and push to `main`. `publish.yml` and
  `worker.yml` are manual stubs until Phase 7.

**Decided**

- Names: top-level types start with `Extension` (`ExtensionManifest`, `ExtensionPermission`,
  `ExtensionAPIVersion`, `ExtensionIndexFile`). Messages nest in `ExtensionWire`, like
  `SettingsWire`; trees nest in `ExtensionUI`, so `List`, `Form` and `Image` never shadow SwiftUI.
  The index type is `ExtensionIndexFile` because `ExtensionStoreIndex` reads too close to the app's
  planned `ExtensionIndexStore`.
- Vendoring: every declaration and extension is `nonisolated` and `public`, so the files compile in
  the app's module as they are. They were type-checked as one module under the app's settings, and
  also under MainActor default isolation, so adopting that setting later needs no change.
- Coding: one enum per direction (`ExtensionWire.ToExtension`, `ExtensionWire.ToMainApp`), as
  `ProcessLink` wants. Every message is a flat object tagged by `type`; a nested variant
  (`input`, `call`, `error`, `ui`, images, form fields) is its own tagged object. Values are
  kebab-case, keys camelCase. Plain `JSONDecoder` works, as `PipeFraming` uses.
- UI: every item, field and action has an `id` unique within a render. An action is only an ID; its
  effects are host calls. Images are SF Symbols or paths inside `assets/`, and decoding rejects a
  path that leaves it. The host filters List and Grid unless the tree sets `handlesSearch`.
  Navigation, per-action shortcuts and Detail metadata wait for a later minor.
- Preferences: `text`, `secret`, `checkbox` and `dropdown`. `start` carries each set one as a bare
  JSON string or bool.
- Validation: plain decoding checks shape and ignores unknown keys, so an older reader survives a
  newer minor. `ExtensionManifest.validated(from:)`, which the CLI will call, checks every rule and
  rejects unknown keys. The one rule the schema cannot state, unique command and preference names,
  lives in Swift alone.
- One manifest type for both copies: `api` is optional, absent in the authored file and stamped by
  `pack`.
- The index drops an entry it cannot decode instead of failing whole, since a newer minor may name a
  permission or mode an older app doesn't know.

**Next:** Phase 2 in `tinycast-extensions`: TinycastKit, the CLI and `hello`.

### 2026-11-28 · Phase 0: remove Raycast extensions

The app no longer runs Raycast extensions, and nothing in the code, docs or website mentions that it
ever did. Raycast import (`.rayconfig` settings, snippets, quicklinks, clipboard and script commands)
is a separate feature and stays.

**Removed**

- The runtime: `Features/Extensions/`, `RaycastRuntime.generated.js`, `Scripts/raycast-runtime/`.
- Its wiring: the extension screen, accessory, toast and back step in the palette; extension rows,
  actions and argument fields in the launcher; extension hotkeys and deep links; the Extensions
  Settings tab, its search entries and Settings calls; its preferences, `settings.json` key, backup
  field, iCloud Sync category and source; the update blocker for a running command.
- `AppEntry.Kind.extensionCommand`, `PaletteMode.extensionCommand` and
  `HotKeyAction.extensionCommand`.
- Shared code only extensions used: the palette's control-list state, two `PaletteScreen` hooks
  (`tabTarget` and the `menuContent` override), `EntryIcon.artwork`, `AppEntry.ownerName` and
  `backgroundRefresh`, `Bundle.installedAppName`, the `menuShortcut` font token, and every part of
  `Zlib` but `gunzip`.
- The `allow-jit` entitlement, the `raycast` and `com.raycast` URL schemes, the Reminders usage
  string, 15 test files and 204 localized strings.
- Docs: `docs/features/extensions.md` and every passage elsewhere; the website's Extensions section,
  feature card, privacy switch and scene.

**Decided**

- `extensionCommand` went too, rather than staying unused until Phase 3. The plan now says so;
  Phase 3 adds the kind back.
- A one-release cleanup, `RaycastExtensionsMigration`, clears what the old runtime left behind:
  - **On each Mac, at launch:** the `extensions`, `extension-data` and `extension-support` folders
    and `extension-commands.json` and `extension-versions.json` in Application Support; the old
    preferences (Show in launcher included), extension hotkeys and menu bar item positions;
    `extension:` keys in favorites, aliases, hidden items and ranking; and the `extensions` section
    of `settings.json`, so the import never reports it as unknown.
  - **In iCloud:** this build re-downloads everything once, because what it syncs changed. Every
    `extensions.` record that arrives is deleted, and so is the synced Show in launcher setting.
  - A Mac still on an older version sees those deletions and drops its Raycast extensions, which it
    would lose at its own update anyway.
  - A user who skips this release keeps the leftovers. Nothing reads them, so that is harmless.
- Show in launcher (`extensionsShowInLauncher`, `extensions.showInLauncher`) goes with the rest for
  now. If native extensions want users' old choice back, drop it from the cleanup before release.
- `extensionsEnabled` is removed, so native extensions start off for everyone and ask for consent
  again.
- iCloud Sync's saved state named the removed category and was decoded strictly, so it would have
  reset every syncing Mac. `SyncLedger` now drops a source or category it no longer knows when it
  loads. That is a lasting rule, not part of the cleanup.
- Native extensions must sync under a new source name, never `extensions`: older Tinycast versions
  still read those records as Raycast installs, and a Mac still on the cleanup release deletes them.

**Comes back later**

- `AppEntry.Kind.extensionCommand` (Phase 3).
- The `Library` row in the naming table, with `ExtensionLibrary` (Phase 5).
- An extensions rule in AGENTS.md and the extension process in `architecture.md` (Phase 9).

**Next:** Phase 1 in `tinycast-extensions`.

## After the cleanup release ships

Once a stable release (`vX.Y.Z`) contains the cleanup, `./Scripts/lint.sh` and the Release workflow
fail on purpose until it is deleted. Then remove, in one change:

1. `Tinycast/Migrations/RaycastExtensionsMigration.swift`.
2. In `AppCore.start()`, the block right after `load()`: the `RaycastExtensionsMigration.run` call
   and the `retired` keys removed from favorites, aliases, visibility and ranking.
3. In `CloudSyncSession.receive`, the `isRetiredRecord` check at the top of the records loop.
4. `Tests/RaycastExtensionsMigrationTests.swift` and its line in `Scripts/run-tests.sh`.
5. Its row in `docs/testing.md` and its row in `docs/migrations.md`.
6. Run `xcodegen generate`, then build, `./Scripts/run-tests.sh` and `./Scripts/lint.sh`.
7. Log it here with the date and the release it shipped in.

Deleting the file alone fails the build at items 2 and 3, so none of them can be missed.
