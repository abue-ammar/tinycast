# 07 — Model purity, environment inputs and main-actor I/O

Status: proposed. [Audit index](README.md). Read [architecture](../architecture.md),
[clipboard](../features/clipboard.md), [snippets](../features/snippets.md) and affected feature invariants.

## Findings

| ID | Confirmed pattern | Priority | Difficulty | Risk |
| --- | --- | --- | --- | --- |
| M01 | Several Model files own persistence, filesystem traversal or watchers, although the documented layer is pure | P2 | Low for moves; Medium for mixed files | Medium |
| M02 | Pure-looking parsing/model entry points default to process environment, home directory or wall-clock reads | P2 | Medium | Medium |
| M03 | Some MainActor stores and repositories synchronously read/write storage and query SQLite | P2, measure first; P1 for demonstrated UI blocking | High for large stores | High |

The import purity check passes. It checks framework imports, not filesystem or clock effects. No
profiling was performed, so synchronous I/O is confirmed but a general UI performance regression is not.

## M01 — Restore the existing layers

Move concrete effect owners into their feature's Service directory without renaming or duplicating
them. Retain Foundation-only implementation where useful: harnesses can compile a Service file too.
Update source lists in `run-tests.sh`; directory position must not become an excuse to stop testing
shipped sources.

| Current Model source | Effect to place in Service | Pure portion to retain |
| --- | --- | --- |
| [SnippetRepository](../../Tinycast/Features/Snippets/Model/SnippetRepository.swift), [SnippetsStore](../../Tinycast/Features/Snippets/Model/SnippetsStore.swift) | File coordination, mutation, watcher descriptors and lifecycle | Templates, source revisions, snapshots/policy values |
| [ClipboardStore](../../Tinycast/Features/Clipboard/Model/ClipboardStore.swift#L170) | Database, extraction/search coordination and blob operations | Clipboard items, filters and value rules currently sharing the file |
| [QuicklinkStore](../../Tinycast/Features/Quicklinks/Model/QuicklinkStore.swift) | SQLite persistence and default storage location | Quicklink values and destination rules |
| [LauncherRankingStore](../../Tinycast/Features/Launcher/Model/LauncherRankingStore.swift), [SearchScopes](../../Tinycast/Features/Launcher/Model/SearchScopes.swift#L41) | Ranking file I/O and bundle scanning | Ranking calculations, normalization and scope definitions |
| [CustomQuickActionStore](../../Tinycast/Features/QuickActions/Model/CustomQuickActionStore.swift), [CustomCommand](../../Tinycast/Features/CustomCommands/Model/CustomCommand.swift#L149) | JSON/preferences stores | Custom action/command values and validation |
| [RoomParkingLedger](../../Tinycast/Features/WindowManagement/Model/RoomParkingLedger.swift), Room/WindowLayout/CustomWindowSize stores | File or preferences persistence | Room/layout values and placement policy |
| [BackupArchive](../../Tinycast/Features/Backup/Model/BackupArchive.swift), [BackupBundle](../../Tinycast/Features/Backup/Model/BackupBundle.swift) | Archive filesystem operations and bundle reads/writes | Manifest and settings formats |
| [ExtensionManifest](../../Tinycast/Features/Extensions/Model/ExtensionManifest.swift#L235), [ExtensionPackageManager](../../Tinycast/Features/Extensions/Model/ExtensionPackageManager.swift#L64) | Manifest loading and executable discovery | Manifest decoding and package-manager identity |

Start with a self-contained repository move. Split mixed files only where it creates a real pure/effect
boundary. Do not add protocols, factories or parallel repository classes with one consumer. Keep
existing owner names, persistence formats, mutation semantics and AppCore wiring. For actor-bound
binding closures such as SettingsFileBinding, place execution in the existing Settings service layer
without duplicating the exhaustive schema or metadata.

Update architecture and feature docs with each move. Snippets' watcher `assumeIsolated` replacements
belong in A02/L02, not in a folder-only commit.

## M02 — Require explicit environment facts

Examples worth correcting:

- [QuicklinkDestination](../../Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift#L33) defaults
  home-directory input to `NSHomeDirectory()`.
- [RaycastQuicklinkImport](../../Tinycast/Features/Quicklinks/Model/RaycastQuicklinkImport.swift#L95) reads
  `Date()` when imported timestamps are absent or invalid.
- [ExtensionBootConfig](../../Tinycast/Features/Extensions/Model/ExtensionBootConfig.swift#L17) reads
  process information and filesystem roots; RenderNode's malformed-date handling also reads the clock.
- [InstalledAILaunch](../../Tinycast/Features/AI/Model/InstalledAILaunch.swift#L49) defaults filesystem
  checks and process environment.
- ChatMessage, ChatSession, ClipboardItem, Quicklink and CustomQuickAction initializers supply wall-clock
  defaults; inspect them together with the effect owner that creates each value.

Pass time, home and environment from the existing coordinator/service/composition boundary. Decode
already-read manifest bytes in Model; load them in Service. Preserve intentional fallback values by
supplying one timestamp per import or operation, rather than silently changing malformed-record behavior.
Remove live-environment defaults from pure entry points once all callers pass them explicitly.

Keep `UUID` identity generation separate from time-based decisions: do not turn every value initializer
into a dependency-injection framework. Use existing value parameters and closures where the environment
fact actually influences policy.

## M03 — Measure and reduce main-actor storage work

Priority inspection points are
[SettingsFileRepository](../../Tinycast/Features/Settings/Service/SettingsFileRepository.swift#L45),
store initialization/load in the table above, ClipboardStore's SQL search/prune paths, and
[Paster.write](../../Tinycast/Features/Clipboard/Service/Paster.swift#L117), which reads image data and
checks file existence before pasteboard mutation. Settings' synchronous file writes can target a user
chosen dotfiles location; disk speed is an environment fact, not guaranteed by a small JSON file.

Use Signposts/Time Profiler with representative large history, cold storage and user-selected folders.
Move demonstrated expensive work to an existing nonisolated worker or repository, returning values to
MainActor. Separate content preparation from the AppKit pasteboard mutation. Do not move a raw SQLite
pointer across tasks; maintain one connection ownership domain, or use the existing off-main search
connection pattern where it already exists.

Preserve ordering, dirty drafts, unsaved edits, source revisions, generations and quit flushing. Reads
that began before a mutation must not overwrite its result. NotesStore/NotesRepository's existing
revision-based approach is a useful local precedent. Do not create an actor per store or add a database
abstraction before a simpler feature-local fix is exhausted.

Keep Debug data under `Bundle.main.bundleIdentifier`, retain authored-data failure behavior, and avoid
new schema migrations or caches. A synchronous bounded operation can remain when measurements show
that making it async would add more complexity than benefit.

## Validation and completion

Run each moved source's harness and then the full suite, lint, build and import purity check. Cover
fixed clock/home inputs, malformed data, unreadable storage, external changes, concurrent mutations,
save ordering and late results. Preserve quicklink/clipboard markers, pin order, ranking, settings
partial-edit semantics and capability exclusions from backup.

Measure main-actor time, launch/palette latency and memory before and after M03. Done when pure files
contain decisions over supplied values, effects remain on their existing feature owners, and measured
slow storage paths cannot stall interaction. Keep folder moves, environment changes and I/O scheduling
in separate commits so behavior regressions can be reverted precisely.
