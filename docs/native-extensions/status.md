# Native extensions: status

Last updated 2026-11-28. The design is [native-extensions-plan.md](native-extensions-plan.md); this
file records what is done, what was decided on the way, and what comes next.

## Phases

| Phase | What                                   | Repo                   | State            | Branch / PR                 | Date       |
| ----- | -------------------------------------- | ---------------------- | ---------------- | --------------------------- | ---------- |
| 0     | Remove Raycast extensions              | app                    | Done, not merged | `ext/0-remove-raycast`      | 2026-11-28 |
| 1     | The contract                           | extensions             | Done             | `main`                      | 2026-11-28 |
| 2     | SDK, CLI and a first extension         | extensions             | Done             | `main`                      | 2026-11-28 |
| 3     | The host                               | app                    | Done             | `ext/3-host`                | 2026-11-28 |
| 4     | Host-drawn UI                          | app                    | Not started      | `ext/4-ui`                  |            |
| 5     | Permissions                            | app                    | Not started      | `ext/5-permissions`         |            |
| 6     | Menu bar and background refresh        | app                    | Not started      | `ext/6-menu-bar-background` |            |
| 7     | Publishing pipeline and install counts | extensions, Cloudflare | Not started      |                             |            |
| 8     | Installer, updates and Store           | app                    | Not started      | `ext/8-installer-store`     |            |
| 9     | Docs, skills and launch                | both                   | Not started      | `ext/9-docs`                |            |

App step branches come off `native-extensions` and merge back into it. The extensions repo commits
to its own `main`.

## Log

### 2026-11-28 · Phase 3, part 2: the launcher and palette surface

`hello`'s three commands run from the Tinycast Dev palette, and both prototype checks pass.
`./Scripts/run-tests.sh` passes (108 harnesses), the Debug build adds no warnings, `./Scripts/lint.sh`
is clean and `Model/` imports no UI framework.

**Built**

- `AppEntry.Kind.extensionCommand`, published after System Settings. Rows come from manifests, so
  listing starts no process: title from the command, subtitle the extension's name, icon the manifest's
  PNG through a new `EntryIcon.image`.
- `ExtensionCommandID` (`Model/`) spells and reads the entry ID `extension-command:<id>/<command>`;
  `ExtensionUI+Rows` says what the screen selects and acts on for each tree.
- `HotKeyAction.extensionCommand` (`hotkey.extensionCommand.<id>/<command>`), indexed in
  `boundExtensionCommandIDs`. Favorites, aliases, hiding, ranking and links use the existing paths.
  Settings › Extensions lists each command with its alias, shortcut and launcher checkbox. Aliases and
  chords sync in Hotkeys & Aliases and wait on a Mac until the command's row exists there.
- `ExtensionCoordinator`: the rows (read off-main, on switch changes, launcher opens and the pane), the
  one run funnel and the screen's session. Listing moved there from `ExtensionManager`.
- `PaletteMode.extensionCommand` and `ExtensionScreen`: the search field (the tree's placeholder), the
  back step, Loading… until the first render, then one line with the tree's type and revision. ↵ sends
  the selected row's first action, ⌘K lists its actions; selection and, when the tree handles search,
  the query reach the extension as events. Leaving the screen sends `stop(closed)`.
- `RaycastExtensionsMigration` also deletes, as they arrive, the `extension:` aliases and chords the old
  runtime synced in Hotkeys & Aliases, which Phase 0 left in iCloud. Its hotkey rule narrows to
  `hotkey.extensionCommand.extension:`, so native chords survive it.

**Checked in Tinycast Dev**

- Off: "greet" finds no extension row. On: Greet, Copy Greeting and Clock appear. Greet opens at
  `list · revision 1`, Wave makes `revision 2`, and Escape ends its process at once. Copy Greeting copies
  "Hello from Tinycast!", shows Copied and exits. Clock exits between 26 and 36 seconds after its run.
  Running Copy Greeting stopped a running Clock: one process per extension.
- Memory (`footprint`): 59 MB with extensions off from launch; 60 MB after using all three commands;
  60 MB once extensions are switched off in the same session, with no `hello` process left.
- **macOS counts a spawned extension as Tinycast: passes.** A temporary `tcc-probe` extension (deleted,
  never committed) listed `~/Desktop` and showed "Desktop: 4 items". TCC logged
  `responsible=com.abueammar.tinycast.dev`, `accessing=com.abueammar.tinycast.ext.tcc-probe`, and
  decided `kTCCServiceSystemPolicyAllFiles` for `subject=com.abueammar.tinycast.dev` (allowed, set by the
  user). No prompt appeared because Tinycast Dev already holds Full Disk Access, so the grant used was
  Tinycast Dev's.
- **A Developer ID extension that was never notarized runs without a prompt: passes.** `hello` packed
  with `--identity "Developer ID Application: … (J656U8XZ93)"`, zipped with `ditto`, served on
  127.0.0.1 and downloaded on an `.ephemeral`, `urlCache = nil` session (SHA-256 unchanged), unpacked
  with `ditto -x -k`. The bundle carried `com.apple.provenance` and no `com.apple.quarantine`.
  `spctl -a -t exec` rates it "rejected, Unnotarized Developer ID", but `syspolicyd` only scanned it at
  exec: Greet and Copy Greeting ran with no prompt. `ExtensionSignatureService` accepts it for team
  J656U8XZ93 and id `hello`, and refuses another team or id.

**Decided**

- A menu-bar command run from the palette closes the palette and runs like a no-view command until
  Phase 6 draws its item; its snapshot goes unused and the process idles out.
- The screen counts as shown while it is the palette's mode, hidden or not, so a preserved screen keeps
  its process until Pop to Root Search (90 seconds at most) changes the mode.
- Phase 3 rows are unfiltered: the host's List and Grid filtering lands with the drawn list in Phase 4.
- Native commands key on `extension-command:`, not the old runtime's `extension:`. Sharing the prefix
  would have left its synced aliases, chords and favorites impossible to tell from native ones, so the
  cleanup could never clear them from iCloud. Now every `extension:` key is a leftover, and the
  cleanup removes all of them.
- Extension command shortcuts ride neither backups nor `settings.json`, like Apple Shortcuts.
- iCloud Sync of installed extensions is planned as Phase 8's task 30: one `installedExtensions`
  record per id, each Mac installing from the Store itself and only while its own Extensions switch
  is on. The plan's iCloud Sync contract has the rules.
- The screen's line is `Text(verbatim:)`, so the catalog never holds text Phase 4 replaces.

**Next:** Phase 4 draws List, Detail and Actions, then Grid and Form, inside `ExtensionScreen`.
`hello`'s icon is a flat gray placeholder; a real one makes the launcher row readable.

### 2026-11-28 · Phase 3, part 1: the host engine

The main app can vendor the protocol, decide what the Store index allows, check a bundle's signature,
and run one extension process from spawn to exit. No palette surface yet; that is part 2. The packed
`hello` runs through the real `ExtensionSession` in a harness. `./Scripts/run-tests.sh` passes, the
Debug and Release builds add no warnings, `./Scripts/lint.sh` is clean and `Model/` imports no UI
framework.

**Built**

- `Scripts/sync-extension-protocol.sh <tag>` clones `tinycast-extensions` over SSH and writes
  `Model/Protocol/*.generated.swift`, each with a header naming the tag. Vendored at `v1.0.0`;
  SwiftLint skips the folder and AGENTS.md lists it as generated.
- `ExtensionIndex` (`Model/`): `canInstall`, `status(of:)` (current, update, pinned, needs a newer
  Tinycast, revoked) and `updates(for:)` for auto-update and Update All. Revoked beats a pin; a revoked
  newer version is never offered; an installed extension missing from the index needs a newer
  Tinycast.
- `ExtensionSignatureService`: Developer ID, `TinycastExtensionsTeamID` from Info.plist and the
  identifier `com.abueammar.tinycast.ext.<id>`. Without the team ID it refuses everything, so Release
  runs nothing until Phase 7.
- `ProcessLink.spawn`: a frame limit per link (roles keep 32 MB, extensions use
  `ExtensionWire.maximumFrameBytes`), every pipe close-on-exec, an optional stderr pipe, and
  `terminate()`.
- `ExtensionSession`: spawning → running → stopping → gone. Renders apply only with a newer revision;
  requests are answered while running and stopping; `finish` calls back once and sends `stop`; the
  idle delay counts only while no surface shows it (`isShown`); a process still alive 5 seconds after
  `stop` is killed. A text reply too big for a frame becomes `failure`, and stderr is read all the
  time, keeping its last 16 KiB for the log.
- `ExtensionManager`, wired in `AppCore.start()`: off stops every process and refuses every run; one
  process per extension, a user run stopping the current one and waiting for it to exit, a background
  run giving way. Before every launch: the command exists, `canRun(api)`, the signature. `start`
  carries the data folder `ExtensionData/<id>/`, the locale and the appearance. A user run's failures
  and `finish` HUD go through `showMessage`.
- `ExtensionHostCallRunner`: copy, read clipboard, HUD, `https` open, close palette and open
  Permissions settings. Paste and selected text reply `failure` until Phase 5.
- `extensionsEnabled`, off by default: `extensions.enabled` in `settings.json`, carried by backups,
  never synced. An Extensions Settings pane holds it.
- Developer mode, Debug only: a toggle in that pane and `DeveloperExtensions/` in Application Support,
  whose bundles run without the Store or the signature check. No `settings.json` key, backup field or
  sync; Release contains none of it.
- Harnesses: `ExtensionModelTests`; `ExtensionSessionTests` (`hello` from `TINYCAST_HELLO_BUNDLE`, the
  harness itself as a stand-in for a stale render, a request after `stop` and a process that ignores
  it); new `PipeFramingTests` cases.

**Decided**

- The switch reuses `extensionsEnabled`, and `RaycastExtensionsMigration` no longer deletes it. A
  key the migration retires is taken back, and dropped from the migration, whenever a native part
  needs it. So a Mac whose old runtime was on starts with native extensions on, which reverses Phase
  0's "start off for everyone".
- `extensions` is a known `settings.json` section now, so the migration strips only the old
  `extensions.showInLauncher` key.
- Idle delay 30 seconds: a restart costs about 33 ms, so a longer one saves nothing and holds 2–5 MB,
  and 30 seconds equals the background limit. Stop-to-kill 5 seconds: long enough for an action
  chosen as a menu closes to fetch and copy. stderr tail 16 KiB.
- A run the user didn't start gets `failure` for HUD, open, close palette and open Permissions
  settings, rather than a success that showed nothing.
- `Process` already closes other descriptors in its children on macOS 27: a harness check passes with
  or without close-on-exec. The marking stays for any spawn that bypasses `Process`.
- The harness skips the `hello` cases with a reason when no packed `hello` is beside this checkout,
  since the extensions repo is private; no CI runs harnesses.
- Developer-mode text is `Text(verbatim:)`, so the catalog holds only what Release ships.

**Next:** Phase 3, part 2: `AppEntry.Kind.extensionCommand`, rows from manifests and the palette
screen that shows a session. `RaycastExtensionsMigration` still deletes `hotkey.extensionCommand.*`
defaults and `extension:` keys in favorites, aliases, hidden items and ranking: whichever of those
native commands use, drop from the migration in the same change. Phase 8 does the same for the
`extensions` folder in Application Support, which is `Extensions/` on a case-insensitive disk.

### 2026-11-28 · Phase 2, part 2: the `tinycast` CLI and `hello`

`tinycast new | validate | build | pack` work, and `hello` runs packed over real pipes. A fresh
`tinycast new demo` validated, built and packed, then was deleted. `tinycast pack hello` makes a
universal (`x86_64 arm64`), ad-hoc signed `hello.tcext` with identifier
`com.abueammar.tinycast.ext.hello` and the hardened runtime; the binary is 2.5 MB. `swift build` and
`swift test` pass with warnings as errors, the schema check passes, and `swift format lint` is clean.

**Built**

- `TinycastCLI`: Foundation only, with `Process` for `swift`, `git`, `lipo`, `otool` and `codesign`,
  and a hand-written parser. Each failure is one line, `<repo-relative file>: <rule>`; exit 0, 1 for a
  failed rule, 2 for wrong usage.
- `validate [<id>…] [--index <file>] [--base <ref>]`: every `ExtensionManifest.validated(from:)`
  issue, id equals folder, `Package.swift` (read with `swift package dump-package`: the SDK by path
  alone, one executable product named `<id>`, one target), a 512×512 PNG icon, README with no HTML or
  images outside code, a `## <version>` CHANGELOG section, screenshots `1.png`…`5.png` with no gap,
  2000×1250, at most 1 MB. With `--index`, a version not below the published one. With `--base`, a
  higher version when `Sources/` changed since the merge base.
- `build <id>`: `swift build -c release --arch arm64 --arch x86_64`, then the binary rules: both
  architectures, linked libraries only Foundation, CoreFoundation, CryptoKit, `/usr/lib/swift`,
  `libSystem` and `libobjc` (`otool -L`), and no `dlopen` import (`otool -Iv`).
- `pack <id> [--identity <name>]`: `extensions/<id>/.build/<id>.tcext` as the Packaged extension
  contract says, `api` stamped from `ExtensionAPIVersion.current`. It reruns the binary rules, signs
  with `--options runtime` and the fixed identifier, and verifies the signature. `--identity` adds
  Developer ID and a timestamp.
- `new <id>`: manifest, `Package.swift`, one view command, a placeholder icon, README, CHANGELOG. It
  checks the id through `validated(from:)` and that the folder is free.
- `extensions/hello`: `greet` (List, a Wave action), `copy-greeting` (no-view, copies, HUD) and
  `clock` (menu bar, `10m`).
- Tests: `TinycastCLITests` has one counter-example per validate rule (a scaffold with one change),
  every protocol manifest counter-example run through `validate`, `--index` and `--base` (a temporary
  git repo), the binary rules on `otool` and `lipo` output, the parser and the exit codes.
  `EndToEndTests` spawns the packed `hello` with a verbatim copy of the app's `PipeFraming`: start →
  render → event → render → stop, a no-view command's request, reply and `finish`, a menu-bar render,
  and the bundle's identifier, stamp and signature.
- `ci.yml`: SDK build, tests and schema, then validate (with `--base` on PRs), build and pack every
  extension, then the end-to-end test.

**Decided**

- Binary rules run in `build`, and again in `pack`, so `validate` stays fast and source only and
  nothing unchecked gets packed. The `dlopen` check sees direct calls only; review stays the guard.
- The end-to-end test is a Swift Testing suite skipped unless `TINYCAST_HELLO_BUNDLE` names the
  bundle. Plain `swift test` skips it at no cost; CI runs it after `pack` in under a second. Building
  and packing inside `swift test` would add a universal release build to every run.
- Ad-hoc bundles get the hardened runtime too, so developer mode runs what CI ships.
- The CHANGELOG needs the current version's section always, not only when `Sources/` changed.
- The bundle's `Info.plist` has `CFBundlePackageType` `BNDL`, so Launch Services never lists an
  extension as an app.
- SwiftPM names a path dependency after its folder, so the repo folder must stay
  `tinycast-extensions`.
- TinycastKit fixes from review: a render too large to send leaves the revision and the last tree
  as they were; a no-view run that returns after `stop` sends no `finish`; `ViewCommand.handle`
  states that actions can arrive while a search is still awaiting.
- The scaffold's target and `@main` type are `<Name>Extension`, so no id clashes with an SDK name.
- `Process` children inherit every open descriptor, so a pipe another child holds never ends. The
  CLI and the end-to-end test mark their pipes close-on-exec. The app's `ProcessLink.spawn` may need
  the same once it spawns extensions side by side.

**Next:** tag `v1.0.0`, then Phase 3. Phase 7's `publish.yml` calls `tinycast build` and
`tinycast pack --identity`, and passes `--index` to `validate`.

### 2026-11-28 · Phase 2, part 1: TinycastKit

`TinycastKit` runs a command end to end: it reads `start`, renders, handles events, calls the host
and exits after `stop`. Four contract fixes went in first; the contract is now what `v1.0.0` will
tag, and `api` stays `1.0`. `swift build` and `swift test` pass with warnings as errors, the schema
check passes, and `swift format lint` is clean.

**Built**

- Contract fixes: `Scripts/check-schema.sh` now fails unless ajv gives every fixture exactly one
  verdict, so a schema that is not JSON or does not compile fails it; it also checks the schema
  accepts the `invalid-swift-only/` fixtures. `Start.arguments` is gone. `HostCall` gains
  `openPermissionSettings`. `ExtensionWire.maximumFrameBytes` is 8 MB.
- The public API: `Extension` (the `@main` type and its commands by name), `Command` (`.view`,
  `.noView`, `.menuBar`), `ViewCommand` and `MenuBarCommand` (an `@Observable` class with a `body`,
  `run()` and a handler), `CommandContext` (the start reason, locale, appearance, preferences, data
  folder and every host call), `Preferences` (`text`, `bool`, `choice`) and `DataFolder` (JSON
  `read`, `write` and `remove` by file name). It re-exports `TinycastProtocol` and `Observation`.
- Inside: `CommandSession` (one run), `HostLink` (frames, reader, writer and the call table) and
  `Framing` (the `PipeFraming` format).
- `TinycastKitTests`: 20 tests drive sessions in-process through pipes: render, event and render
  again; a burst of changes as one render; events handled in order; broken input; host calls and
  their replies; `permissionOff` shown and
  handled; cancellation by the caller, by `stop` and by the main app going away; an action just
  before `stop`; stdio redirection; preferences, the data folder and the frame limit.
- The plan's `hello`, written against the API in a scratch package, built and ran through real
  pipes; it links Foundation and Swift runtime libraries only.

**Decided**

- Renders come from `Observations { command.body }`, so an author never asks for one. Changes in
  one main-actor step make one render; a tree equal to the last one sent is skipped. The first
  render goes out before `run()` starts.
- Author code and the session run on the main actor. Reads and writes run on their own serial
  queues, and the reader hands each reply straight to its waiting call through a `Mutex` table, so
  a reply arrives while author code is busy, and after `stop`.
- Two task groups own every task. In each, one task handles events one at a time in arrival
  order, so a later search never lands before an earlier one. Events from an older render still
  arrive; their IDs are the author's to look up. `stop` cancels updates (renders, `run()`, search,
  selection, a no-view run) but waits for actions and submits already received, so a menu item
  chosen as the menu closes still runs. Then every call still waiting throws `CancellationError`,
  the writer drains and the process exits 0, or 1 if the input broke. At end of input the calls
  are cancelled first.
- `permissionOff` left uncaught shows one Detail whose action calls `openPermissionSettings`, for a
  view command or a no-view command the user started. A menu-bar command or a background run logs
  it to stderr. A new host call beat a `tinycast://` URL for `open`, a reserved action ID, and a
  host-drawn permission tree. The view's text is English for now.
- Frames use private copies of fd 0 and fd 1. fd 1 then points at stderr and fd 0 at `/dev/null`,
  so `print` goes to stderr and never into a frame.
- Host calls are methods on `CommandContext`, not a `Host` type, which Foundation already has.

**Next:** Phase 2, part 2: the `tinycast` CLI and `extensions/hello`. For Phase 3, the host must read
`maximumFrameBytes` (`ProcessLink` keeps its own limit today), answer requests until the extension
exits, reply `failure` when a reply would pass the limit, and show a render from a no-view command
the user started.

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
3. In `CloudSyncSession.receive`, the `isRetiredRecord` and `isRetiredEntry` checks in the records
   loop, and `deleteRetired`.
4. `Tests/RaycastExtensionsMigrationTests.swift` and its line in `Scripts/run-tests.sh`.
5. Its row in `docs/testing.md` and its row in `docs/migrations.md`.
6. Run `xcodegen generate`, then build, `./Scripts/run-tests.sh` and `./Scripts/lint.sh`.
7. Log it here with the date and the release it shipped in.

Deleting the file alone fails the build at items 2 and 3, so none of them can be missed.
