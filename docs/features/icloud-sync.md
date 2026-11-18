# iCloud Sync

Keeps settings and content the same on every Mac signed in to one iCloud account, through CloudKit's
private database and `CKSyncEngine`. It is off by default and turned on in **Settings → iCloud Sync**.
What syncs, and how the pane presents it, follows Raycast's Cloud Sync. The feature lives in
`Features/CloudSync/`, and each feature owns the source that reads and writes its own data.

## Invariants

- **A Mac never uploads before its first full fetch.** Every category joins through a fetch from
  the start, and an item this Mac holds that it has never synced is merged rather than pushed:
  - the server wins for settings, so a new Mac adopts the others' setup;
  - a note or snippet with the same file name but different content is renamed aside, so both
    survive;
  - a duplicate of an arriving item is removed ("Removing duplicates"); a duplicate MCP server
    first hands its credentials and trust to the arriving one.

  The same merge runs when sync or a category is turned back on, a notes or snippets folder
  moves, the account switches, or iCloud resets its encrypted data. Turning sync off forgets the
  ledger and keeps every Mac's data and the copy in iCloud. A join whose fetch fails runs again at
  the next fetch, so this Mac's own items still upload.

- **An unavailable source is paused, never empty.** A source answers `nil` while it can't speak
  for its data (AI off, Snippets off, a folder missing, a store unreadable) and `nil` never
  produces a deletion. What arrives meanwhile is deferred to disk and applied once it can be.
- **Applying never echoes.** After an apply, the ledger records the source's own re-read, not the
  incoming payload, so what a Mac couldn't take (a clashing chord, a missing app) stays local and
  isn't sent back. Identical content is never rewritten, so a note's date doesn't move, and a
  re-fetch skips every version this Mac already holds by its change tag.
- **Last write wins per item.** `modifiedAt` is stamped when a change is detected, and ties go to
  the server. An edit beats a remote delete and is uploaded again. The open note with unsaved
  edits keeps them.
- **No executable and no grant crosses.** Custom commands never sync. An MCP server's trust is
  each Mac's own. A synced fallback list can turn Run Shell Command off, never on. An extension
  installs only where Extensions is on, since that switch is the consent to run third-party code.
  Every feature switch (`*.enabled`) stays per Mac, as in Raycast.
- **Secrets never sync.** AI keys, MCP credentials, extension passwords, OAuth tokens and anything
  in the Keychain stay where they are. User content travels in `encryptedValues`.
- **A delegate callback never awaits `fetchChanges` or `sendChanges`.** CKSyncEngine traps on it.
  Every `stateUpdate` is persisted, and the ledger, not the engine, is the record of what still
  has to upload, so a hard failure is re-queued on the next pass.
- **A newer format pauses sync.** A record with a higher `schemaVersion` stops this Mac with
  "update Tinycast" and is never rewritten.
- **Deletions from another Mac go to the Trash** for notes and snippets.
- **`iCloudSyncEnabled` and the category choices never ride a backup or `settings.json`.** Sync
  sends this Mac's data off it, so only the pane may turn it on.

## What syncs

| Group   | Category                                                                     | Data                                                                  |
| ------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Content | AI Commands & Presets                                                        | chat presets, custom quick actions, the system prompt                 |
| Content | AI Chat History                                                              | chats without attachments, and the retention setting                  |
| Content | Dictation                                                                    | `dictation.*` but the model and microphone                            |
| Content | MCP Servers                                                                  | the server list, without credentials or trust                         |
| Content | Quicklinks · Notes · Snippets                                                | the items; notes and snippets by file name                            |
| Content | Window Layouts                                                               | custom sizes, layouts and rooms                                       |
| Content | Extensions                                                                   | store installs and their text, checkbox and dropdown preferences      |
| General | Open at Login · Show in Menu Bar · Appearance · Interface Size · Window Mode | one setting each                                                      |
| Always  | Hotkeys & Aliases                                                            | every `*.commands`, app, pane and action record, plus content rows'   |
| Always  | Favorites & Fallback Order                                                   | both lists                                                            |
| Always  | Other Settings                                                               | every other `settings.json` key `SyncSettingScope` doesn't keep local |

Never: clipboard history, custom commands, search ranking and frecency, credentials, and
Mac-specific settings (feature switches, folders, language, search scopes, palette position).

## Layout

| File                                              | Role                                                                   |
| ------------------------------------------------- | ---------------------------------------------------------------------- |
| `Model/SyncCategory.swift`, `SyncExclusion.swift` | What the pane lists, and why                                           |
| `Model/SyncSourceID.swift`                        | Each kind of item, its category, and its hashed record name            |
| `Model/SyncLedger.swift`                          | Per-item versions, server metadata and pending uploads; LWW lives here |
| `Model/SyncSettingScope.swift`                    | Every `SettingsFileKey` to a category or local (exhaustive)            |
| `Model/SyncEntryKey.swift`                        | Launcher keys that name a path, spelled the same on every Mac          |
| `Service/SyncSource.swift`                        | The protocol each feature's source implements                          |
| `Service/CloudSyncSession.swift`                  | One `CKSyncEngine` and its delegate: events to sources and back        |
| `Service/CloudSyncRecordCodec.swift`              | Item ⇄ `CKRecord`; payloads over 512 KB travel as assets               |
| `Service/CloudSyncStateStore.swift`               | Engine checkpoint, ledger, deferred arrivals, this Mac's identity      |
| `Service/CloudSyncAvailability.swift`             | Entitlement and account checks, push registration                      |
| `UI/CloudSyncCoordinator.swift`                   | Lifecycle, change watching, the pane's state and actions               |
| `Settings/`                                       | The pane                                                               |

The sources sit with their features: `SettingsSyncSource` (through the shared `SettingsBindingSet`),
`EntryShortcutSyncSource` and `LauncherListSyncSource`, `SnippetSyncSource`, `NoteSyncSource`,
`QuicklinkSyncSource`, `ChatSyncSource`, `ExtensionSyncSource`, and `RecordSyncSource` factories for
chat presets, quick actions and MCP servers.

## CloudKit

One zone, `Tinycast`, and one record type, `SyncItem`, for everything, so a new kind of data never
changes `Config/CloudKit/schema.ckdb`. A record's name is its source plus a hash of its key; the key
and payload are encrypted fields. Each channel has its own container, `iCloud.<bundle id>`, so
stable, beta and Dev never share data.

Pushes deliver changes within seconds. A 15-minute poll, waking from sleep and opening the pane
fetch as well, because pushes on macOS can be late.

Production takes a schema only through the CloudKit Console's **Deploy Schema Changes**, and a field
it lacks fails every save there, so the release workflow checks it before it builds. See
[release.md](../release.md) and [signing.md](../signing.md).
