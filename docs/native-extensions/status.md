# Native extensions: status

Last updated 2026-11-28. The design is [native-extensions-plan.md](native-extensions-plan.md); this
file records what is done, what was decided on the way, and what comes next.

## Phases

| Phase | What                                   | Repo                   | State            | Branch / PR                 | Date       |
| ----- | -------------------------------------- | ---------------------- | ---------------- | --------------------------- | ---------- |
| 0     | Remove Raycast extensions              | app                    | Done, not merged | `ext/0-remove-raycast`      | 2026-11-28 |
| 1     | The contract                           | extensions             | Not started      |                             |            |
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
- No migration. Old files, UserDefaults keys and CloudKit records stay on disk, unread.
- One known effect of that: with the settings file on, `extensions.showInLauncher` shows an
  "unknown setting" message at each launch until any change in the app rewrites the file. This is a
  deliberate exception to the settings-file rule that a removed key ships a migration.
- iCloud Sync's saved state named the removed category, and was decoded strictly, so it would have
  reset every syncing Mac. `SyncLedger` now drops a source or category it no longer knows when it
  loads. That is a lasting rule, not a migration, and covers later removals too.

**Comes back later**

- `AppEntry.Kind.extensionCommand` (Phase 3).
- The `Library` row in the naming table, with `ExtensionLibrary` (Phase 5).
- An extensions rule in AGENTS.md and the extension process in `architecture.md` (Phase 9).

**Next:** Phase 1 in `tinycast-extensions`.
