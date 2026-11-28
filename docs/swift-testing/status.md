# Swift Testing migration: status

Temporary; deleted with [README.md](README.md) in the last commit. Read the brief first.

**Next: B5 · Palette input** (build mode)

Statuses: `todo`, `next`, `done <commit>`. Exactly one batch is `next`. Numbers are line counts of
the old harness.

## Phases

| Batch | Title                                  | Mode  | Rows | Status |
| ----- | -------------------------------------- | ----- | ---- | ------ |
| P0    | Docs describe the end state            | build | –    | done   |
| P1    | Pilot: target, host, runner, 4 suites  | plan  | 4    | done   |
| T     | Triage: find what does not belong      | build | –    | done   |
| R1    | Remove the benchmarks                  | build | 8    | done   |
| R2    | Remove approved candidates             | build | –    | done   |
| R3    | Remove the extension harnesses         | build | 13   | done   |
| P2    | Peer fixtures for self-run harnesses   | plan  | 3    | done   |
| B1    | Launcher, search, files                | build | 13   | done a2dcde17 |
| B2    | Calculator, calendar, dictionary       | build | 3    | done c1a0118e |
| B3    | Clipboard, emoji                       | build | 6    | done 6a15630e |
| B4    | Palette and design system              | build | 9    | done   |
| B5    | Palette input                          | build | 9    | next   |
| B6    | Dictation, hotkeys, platform           | build | 9    | todo   |
| B7    | Window management                      | build | 8    | todo   |
| B8    | Commands, links, quick actions         | build | 6    | todo   |
| B9    | Notes                                  | build | 2    | todo   |
| B10   | Settings, backup, sync, updates        | build | 8    | todo   |
| B11   | AI providers                           | build | 4    | todo   |
| B12   | AI chat and MCP                        | build | 3    | todo   |
| B13   | Raycast import                         | build | 1    | todo   |
| H     | Helper-only sources                    | plan  | 2    | todo   |
| S1    | Stand-ins: small                       | plan  | 5    | todo   |
| S2    | Stand-ins: hotkeys                     | plan  | 2    | todo   |
| S3    | Stand-ins: snippets, dictation field   | plan  | 2    | todo   |
| S4    | Stand-ins: clipboard, custom commands  | plan  | 2    | todo   |
| S5    | Stand-ins: uninstall, quicklinks       | plan  | 2    | todo   |
| S6    | Stand-ins: app installation            | plan  | 1    | todo   |
| F     | Final: clean-up and sign-off           | build | –    | todo   |

Modes are explained in the brief: _plan_ means the session proposes and you approve before it
builds.

## P1 · Pilot

Infrastructure, in this order. Each item is a decision in the brief; this list is the work.

- [x] `project.yml`: `TinycastTests` (`bundle.unit-test`, sources `Tests/TinycastTests`, depends on
      `Tinycast`, hosted by the Debug app); `PRODUCT_MODULE_NAME: Tinycast` on the app; the `Tinycast`
      scheme's test action runs it. `xcodegen generate`.
- [x] Test host: `TinycastLaunch.main()` runs a bare `NSApplication` when hosting tests.
      Done: the host sees `XCTestConfigurationFilePath` and runs `NSApplication.shared.run()`, before
      `pinLanguage()` can write the dev app's prefs.
- [x] Signing works for the hosted bundle with the local self-signed identity and with
      `CODE_SIGNING_ALLOWED=NO`; write down whichever the runner needs.
      Both pass. The decision-6 command signs with `Tinycast Self-Signed` like any local build, so it
      never replaces the signed dev app in `build/DerivedData` with an unsigned one.
- [x] `Tests/TinycastTests/Support/`: the fixture-loading and scratch-directory helpers
      `docs/testing.md#writing-a-suite` names.
      `ScratchDirectory` (removed in `deinit`) and `Fixture.url(_:)` (the bundle's `Fixtures/` folder).
- [x] Delete `Scripts/run-tests.sh`, its call in `Scripts/sync-lsp.sh`, and any task or doc that runs
      it. Unconverted harnesses stay in `Tests/` uncompiled, as source for their batch.
- [x] `.swiftlint.yml` custom rules, no new script: the `Model/` purity rule, and the old-shape rules
      from `docs/testing.md#rewrite-never-transliterate` scoped to `Tests/TinycastTests/`. Prove each
      fails on a deliberately bad file, then delete that file. Remove `Scripts/check-tests.sh` and
      its call in `lint.sh`.
      Proved: probe files under `Model/` and `Tests/TinycastTests/` hit all 11 rules, comments and
      strings hit none; both probes deleted, lint clean.
- [x] `Scripts/sync-lsp.sh` and the VS Code build task index the test target (`build-for-testing`).
- [ ] Xcode's test navigator lists and runs the suites, down to one test.
      `-enumerate-tests` lists every test and `-only-testing:'…/newCopyEndsTheWalk()'` runs one;
      the navigator itself is for the user to look at.
- [ ] Add SweetPad to `.vscode/extensions.json`'s recommendations. The user confirms it lists and runs
      the suites in VS Code's Testing view; write any setting it needs into `.vscode/settings.json`
      and `docs/development.md#tests-in-the-editor`.
      Recommended; the Testing view awaits the user's check.
- [x] Measure one full run of the decision-6 command and write the wall time here.
      69 s cold (first build of the app and target), 5 s warm, 3 suites.
- [x] Confirm `docs/testing.md#writing-a-suite` matches what the pilot found; fix it, not the code,
      where they differ.
- [x] The 4 pilot suites are the reference every later batch copies: each is a from-scratch design,
      not a converted harness. Name them in the brief's Work section as the examples to follow.
      All four are named there.

Suites:

- [x] PasteSequenceTests · 159 · pure `Model/`
- [x] FormInputTests · 305 · AppKit on the main actor · 3 undo checks removed, see Removal candidates
- [x] MCPStdioTests · 172 · fixtures (`Tests/ai-fixtures/mcp-stub.js`)
- [x] AppleIntelligenceTests · 180 · opt-in `TINYCAST_TEST_APPLE_INTELLIGENCE`

## T · Triage

Read-only except for this file. Apply the brief's decision 13 to every unconverted harness and list
each candidate below, a whole harness or named cases, with its reason. Cheap signals first, then read
only what they flag:

```sh
grep -lE 'TINYCAST_TEST_|ProcessInfo.*environment' Tests/*.swift      # opt-in, machine-dependent
grep -lE 'NSWorkspace.*(open|launch)|NSRunningApplication' Tests/*.swift  # drives real apps
grep -lE 'ContinuousClock|DispatchTime|mach_absolute_time' Tests/*.swift  # timing
grep -LE 'expect|check|assert|precondition' Tests/*.swift             # prints, never checks
```

Then stop: the user answers each candidate before R2.

Done. Extension harnesses (R3) and benchmarks (R1) were left out. Two candidates, below. Every other
signal was a polling wait, a fixed system app (`/System/Applications/Calculator.app`), a stubbed
system call or a self-run peer; the last is an open problem, not a removal.

## R1 · Remove the benchmarks

Delete the 8 files below, `Scripts/benchmark-dictation.sh`, and every doc line that runs or cites them (`grep -rn
'PerformanceTests\|benchmark-dictation' docs AGENTS.md`). Keep measured numbers in `docs/` that
stand on their own; drop the command that produced them.

Done. Docs touched: `calculator.md`, `dictation.md` (the benchmark section), `file-search.md` and
`notes.md`; their numbers stay, and `testing.md`'s baseline row stands on its own.

- [x] FileSearchPerformanceTests · 68
- [x] CalcPerformanceTests · 122
- [x] ClipboardThumbnailPerformanceTests · 130
- [x] EmojiSearchPerformanceTests · 96
- [x] DictationPerformanceTests · 146
- [x] NotesEditorPerformanceTests · 144
- [x] TextDiffPerformanceTests · 110
- [x] ClipboardFilePerformanceTests · 150

## R2 · Remove approved candidates

Delete every **Removal candidates** row marked `approved`: the harness, or the named cases, and doc
lines that cite it. Move rows marked `keep` back to their batch. Candidates found later,
during a batch, are removed in F.

Done. No row was `keep`. The FormInputTests undo checks went in P1 and the Snippets sweep already
covers them. `RelaunchTests` is deleted, and so are `testLaunch`, its gate and its helpers in
`AppInstallationTests`; `launcher.md` drops the opt-in variable. The manual sweep gains
quit-and-relaunch under Settings and backup, and copy-aware launch, Quit, Restart, Force Quit and
Window Layout reuse under Launcher.

- [x] FormInputTests' 3 undo checks (removed in P1)
- [x] RelaunchTests · 211
- [x] AppInstallationTests: the 26 `testLaunch` checks

## P2 · Peer fixtures for self-run harnesses

Each of these runs its own executable as a peer process; hosted, that executable is the Debug app.
Replace every self-run with a peer script in `Fixtures/`, as `MCPStdioTests` does with
`mcp-stub.js`, launched by absolute path with its mode in its own environment. Localization reads the
app bundle's string tables per locale, with no relaunch. No app code changes.

Done. `resolved()` reads the resource's own bundle (user-approved app change), so a resource
pointed at a language's `.lproj` stands in for a relaunch. `Support/` gains `NodeScript` (`MCPStdioTests` uses it too) and
`ScratchDefaults`. Docs: `testing.md` (isolation, three rows), `ai.md`, `dictation.md`.

- [x] LocalizedResourceTests · 95 · 9 languages × 9 resources against each `.lproj`
- [x] DictationWorkerTests · 270 · `Fixtures/Dictation/dictation-worker-stub.js`, run by `node`'s
      absolute path; the competing process is `/usr/bin/lockf -t 0` on the download lock
- [x] AIProviderTests · 2,787 · one suite over 8 files; `Fixtures/AI/codex-app-server-stub.js`
      finds its log through `TC_CODEX_STUB_ROOT`; the captures moved to `Fixtures/AI/`

## B1 · Launcher, search, files

Done. Six suites moved in `36c67aa2` and seven in `a2dcde17`. The full decision-6 run and lint passed.

- [x] FuzzTests · 556 · the 20,000 seeded alignments take about 1 s in Debug at `-Onone`
- [x] FileSearchTests · 501
- [x] FileIndexTests · 295
- [x] FileSearchSessionTests · 247
- [x] MenuSearchTests · 525
- [x] WindowSwitchTests · 147
- [x] RankingTests · 118
- [x] ScopesTests · 265
- [x] AppNameTests · 302
- [x] FavoritesTests · 51
- [x] LauncherFileTests · 70
- [x] AppleShortcutTests · 77
- [x] FallbackTests · 126

## B2 · Calculator, calendar, dictionary

Done. The full decision-6 run and lint passed. `CalcTests` is one suite over eight files: the core,
`+Units`, `+Currency`, `+Dates`, `+TimeZones`, `+Phrases`, `+Wording` and `+NumberFormat`, each test a
table named for the old harness's section. All 1,941 top-level checks are rows, in their old
inputs and environment (fixture rates, offline, region, clock, zone, locale, number format); the
nested loops became cartesian `@Test(arguments:)`. Docs: `calculator.md`, `calendar.md` and
`testing.md`'s one-test example, plus `CurrencyFeed`'s doc comment.

Review fixes in `f2161d8c`: every doc's `xcodebuild test` command carries decision 6's
`-derivedDataPath build/DerivedData -quiet`, and doc comments past 100 characters are shortened.

- [x] CalcTests · 2,887 · 2,687 cases in 185 tests
- [x] CalendarTests · 795
- [x] DictionaryTests · 287

## B3 · Clipboard, emoji

Done. The focused and full decision-6 runs and lint passed. Clipboard search covers 14 queries ×
7 filters across 10 history states. The thumbnail helper signals after reading the source and uses a
pipe to hold the copy in flight. Emoji keyword checks load the packs from the hosted app bundle.

- [x] ClipboardTests · 1,051 · store, classification and color coverage across three files
- [x] ClipboardSyncTests · 219
- [x] ClipboardThumbnailTests · 226 · `Fixtures/Clipboard/thumbnail-helper.sh`
- [x] ClipboardSearchTests · 155
- [x] EmojiTests · 177
- [x] EmojiSearchTests · 242

## B4 · Palette and design system

Done. The focused and full decision-6 runs and lint passed. The catalog checks read the hosted app's
compiled `.lproj` tables instead of compiling or parsing the source `.xcstrings`; the build compiles
both catalogs. Docs: `testing.md` (the `LanguageTests` row and the tripwire baseline), `palette.md`,
`ui.md`, and `ExtensionFormMetrics`' doc comments.

- [x] PaletteSelectionTests · 420 · 4,170 cases in 38 tests, read from the result bundle; that
      count is the tripwire now, with the 729 grid shapes and 128 small shapes as arguments
- [x] AppearanceTests · 128
- [x] LanguageTests · 245
- [x] InterfaceSizeTests · 365 · rounding and growth also cover `menuRowSpacing` and
      `clipboardPreviewPixel`, which only the identity check had
- [x] PalettePlacementTests · 386
- [x] ScrollRevealTests · 77
- [x] RedactionTests · 71
- [x] KeyboardFocusTests · 55
- [x] CalloutTests · 234 · instructions measured in every `AppLanguage`, not only translated ones

## B5 · Palette input

- [ ] CommandEscapeTapTests · 244
- [ ] PaletteEscapeTests · 176
- [ ] PaletteNavigationTests · 341
- [ ] PaletteFilterTests · 87
- [ ] ActionMenuSearchTests · 43
- [ ] PaletteShortcutTests · 142
- [ ] ASCIILayoutTests · 80
- [ ] PaletteTabTests · 110
- [ ] CompactBarTests · 109

## B6 · Dictation, hotkeys, platform

- [ ] DictationTests · 102
- [ ] DictationCueTests · 42
- [ ] DictationVolumeTests · 196
- [ ] PipeFramingTests · 112
- [ ] SharedStateMirrorTests · 97
- [ ] HotKeyTests · 748
- [ ] HyperKeyEngineTests · 378
- [ ] IconCacheTests · 276 · changes `UserDefaults.standard`'s argument domain: `.serialized`
- [ ] EntryIconTests · 211

## B7 · Window management

- [ ] SystemActionTests · 79
- [ ] VolumeTests · 136
- [ ] WindowCommandTests · 1,443
- [ ] WindowPresetTests · 118
- [ ] SpaceGestureTests · 229
- [ ] WindowLayoutTests · 1,020
- [ ] WindowRoomTests · 921
- [ ] WindowFileTests · 181

## B8 · Commands, links, quick actions

- [ ] DeepLinkTests · 383
- [ ] CustomCommandTests · 717
- [ ] UninstallTests · 701
- [ ] QuicklinkTests · 660
- [ ] QuickActionTests · 476
- [ ] TextDiffTests · 73 · ran at `-O`

## B9 · Notes

- [ ] NotesTests · 1,393
- [ ] NotesEditorTests · 1,240

## B10 · Settings, backup, sync, updates

- [ ] CloudSyncTests · 257
- [ ] SettingsBackupTests · 118
- [ ] SettingsFileTests · 423
- [ ] BackupArchiveTests · 410
- [ ] SettingsHistoryTests · 227
- [ ] UpdatesTests · 382
- [ ] UpdateCheckTests · 201
- [ ] SupportTests · 99

## B11 · AI providers

- [ ] PlanUsageTests · 393
- [ ] AIResponsesTests · 378
- [ ] ChatMarkdownTests · 295
- [ ] SyntaxHighlightTests · 369

## B12 · AI chat and MCP

- [ ] AIChatTests · 1,945
- [ ] MCPTests · 326
- [ ] MCPOAuthTests · 632 · fixtures; fixed ports 4962/4963: `.serialized`; saves to the login
      Keychain through `KeychainSecretStore`: give the test its own store

## B13 · Raycast import

Not an extension test: it guards "Import from Raycast" (`.rayconfig`), which stays in the app.

- [ ] RaycastTests · 393 · scrypt takes ~47 s at `-Onone`: needs a cheaper derive in the test, or an
      opt-in gate for the slow case

## H · Helper-only sources

The app target excludes these sources, so `@testable import Tinycast` cannot reach them. Decide how a
test target compiles them (for example a second, unhosted target that builds the helper sources
itself), record it under Decisions, then convert.

- [ ] ClipboardTextTests · 380 · `ClipboardTextExtractor`, `ClipboardTextHelper`
- [ ] DictationInferenceTests · 146 · `Dictation/Helper`

## S1 · Stand-ins: small

The number is how many app types the harness redeclares. Every S batch's plan shows the app-code
change before anything is written: the smallest seam that works, injected at `init` with the shipped
behaviour as its default, never on a hot path (search, ranking, calculation, drawing). The batch then
exercises the changed feature by hand in the Debug app and says so in its commit.

- [ ] PaletteMenuClickTests · 267 · 3
- [ ] MicrophoneMuteTests · 192 · 1
- [ ] OpenCodeMCPTests · 242 · 1
- [ ] LauncherSettingsFileTests · 265 · 3
- [ ] PasteboardTests · 402 · 3

## S2 · Stand-ins: hotkeys

- [ ] HyperKeyTests · 472 · 1, plus `HyperKeyFixtures.swift` (52)
- [ ] HotKeyDispatchTests · 268 · 10, plus `HotKeyDispatchFixtures.swift` (63)

## S3 · Stand-ins: snippets, dictation field

- [ ] SnippetsTests · 2,237 · 4
- [ ] DictationFieldTests · 524 · 12

## S4 · Stand-ins: clipboard, custom commands

- [ ] ClipboardCoordinatorTests · 301 · 12
- [ ] CustomCommandListTests · 171 · 13

## S5 · Stand-ins: uninstall, quicklinks

- [ ] UninstallCoordinatorTests · 189 · 17
- [ ] QuicklinkCoordinatorTests · 668 · 32

## S6 · Stand-ins: app installation

- [ ] AppInstallationTests · 420 · 23; its `testLaunch` checks were removed in R2;
      `--localized-index` relaunches its own executable per language: solve it as P2 does

## F · Final

- [ ] `Tests/` holds only `TinycastTests/`, and `git grep -n run-tests` finds nothing but this folder.
- [ ] Full suite, lint and a Debug build with no new warnings pass.
- [ ] Release build, compared with `main` built the same way (`docs/testing.md#build-and-size-checks`):
      binary growth under 2%; no `.xctest` or test file inside the `.app`; `ENABLE_TESTABILITY` is
      `NO` for Release; the test-host check never fires outside a test run.
- [ ] Launch and palette-open time no worse than `main`, read from the `AppCore.start` and
      `PaletteWindowController.show` signposts in Instruments (three runs each, median).
- [ ] Manual regression sweep (`docs/testing.md#manual-regression-sweep`) on the Release build: Core,
      plus every feature whose app code an S or H batch changed.
- [ ] Suites listed and runnable in Xcode's test navigator and, with SweetPad, in VS Code.
- [ ] Removal candidates approved since R2 are deleted.
- [ ] `git grep -n harness -- docs AGENTS.md CONTRIBUTING.md` finds only AI coding-CLI harnesses
      (`ai.md`, `mcp.md`) and the old baseline row in `testing.md`.
- [ ] Delete `docs/swift-testing/` and the pointer in `AGENTS.md`.

## R3 · Remove the extension harnesses

Deleted, not converted. The Raycast extension runtime is on its way out (`ext/0-remove-raycast`
deletes it and these harnesses), so a Swift Testing rewrite would be thrown away, and keeping them
unrun would leave the old pattern in the tree. Delete each file, `Tests/ext-fixtures/`, their rows in
`docs/testing.md#what-to-run-when`, and doc lines that cite them (`docs/features/extensions.md`).
The extension code itself stays untouched.

Done. `testing.md` drops 8 rows; `extensions.md` keeps every fact the cited tests guarded but no
longer names them, and its runtime section now credits `test.mjs` alone (it always prints console
output, so `EXT_TEST_VERBOSE` is gone); `test.mjs` drops its pointer to `ExtensionTests`.

- [x] ExtensionTests · 3,153 · with `ExtensionTests+MenuBar` and `ExtensionFetchTests`
- [x] ExtensionStoreTests · 284
- [x] ExtensionFormTests · 309 · with `ExtensionListKeyTests`
- [x] ExtensionAccessoryTests · 236
- [x] ExtensionIconTests · 235
- [x] ExtensionCleanupTests · 234
- [x] ExtensionRefreshTests · 239
- [x] ExtensionMetadataTests · 119
- [x] ExtensionVersionTests · 98
- [x] ExtensionSignInTests · 134
- [x] ExtensionImageSizeTests · 56
- [x] SymbolsTests · 112 · `Extensions/Service/SymbolCatalog`
- [x] `Tests/ext-fixtures/`

## After this PR: native-extensions

Not part of this migration; recorded so it is not lost. Native-extensions development is paused until
this PR merges. Then merge `main` into `native-extensions` and its `ext/*` branches. Phase 0 edits about
15 harnesses this migration rewrites (`FuzzTests`, `PaletteEscapeTests`, `SettingsFileTests`, …):
redo those edits in the suites, and write Phase 0's `RaycastExtensionsMigrationTests` as a suite.

## Removal candidates

One row per candidate. The user writes `approved` or `keep` in the last column.

| Harness or case | Reason (decision 13) | Found in | Answer |
| --------------- | -------------------- | -------- | ------ |
| FormInputTests: undo restores the text typed before a programmatic insertion; that undo reaches the binding; a placeholder insertion stays undoable after a menu takes focus | They depend on AppKit's event-loop undo grouping, which the test host doesn't reproduce: under its running `NSApp` the group stays open across run-loop passes and events. Removed in P1; now in the manual sweep's Snippets section | P1 | approved |
| RelaunchTests (whole harness) | Drives real apps: it ad-hoc signs a copy of its own executable as a fixture app, launches it and reopens it through LaunchServices (`/usr/bin/open`), and waits up to 6 s of wall clock for each process event. The fixture's role is the harness's own `main()`; hosted by the app, it would need a test branch in app code, which decision 9 forbids. If approved, quit-and-relaunch belongs in the manual sweep | T | approved |
| AppInstallationTests: the 26 launch checks in `testLaunch` (opt-in `TINYCAST_TEST_APP_LAUNCH`), from "the first selected installation launches" to "fixture processes are cleaned up" | Drives real apps: it compiles a fixture app with `swiftc` at test time, launches, reopens, quits and force-quits it through LaunchServices, depends on workspace notifications a session may not deliver (it already skips two checks without them), and asserts a 5 s wall-clock grace period. The index, file-favourite, language-override and localized-index checks stay in S6. `keep` means an `.enabled(if:)` gate (decision 7) | T | approved |

## Decisions log

Decisions made during the migration, beyond the brief's. Newest last.

- P1: the test host is detected by `XCTestConfigurationFilePath`, which Xcode 27 sets for Swift
  Testing too; it is the one branch app code takes on being under test, as decision 3 requires.
- P1: a test never calls `setenv`. `MCPStdioTests` launches its stub by absolute path and passes the
  mode in `MCPSecretStore.Secrets(environment:)`, so its tests run in parallel (user's choice (a)).
- P1: the host inherits `xcodebuild`'s environment, with no shell `PATH`; a stub run by `env node`
  gets the login shell's `node` linked beside it, which the locator puts first.
- P1: a suite never waits for SwiftUI. `layoutSubtreeIfNeeded()` on the host applies a changed binding
  to its AppKit view synchronously (`FormInputTests`).
- T: harnesses that run their own executable as a peer get peer scripts in `Fixtures/`, designed in
  plan batch P2 (user's choice). Localization reads the bundle's tables per locale, no relaunch.
- T: RelaunchTests and AppInstallationTests' `testLaunch` checks are removed (user approved); R2
  deletes them and adds quit-and-relaunch and app launch to the manual sweep.
- P2: a peer is a stub in `Fixtures/` installed by `NodeScript`; a launcher with no `PATH` of its own
  (`DictationWorker`) runs `node` by absolute path with the script as its first argument.
- P2: a cross-process lock is checked with `/usr/bin/lockf -t 0` (`EX_TEMPFAIL`); it takes the same
  `flock` as the code under test, so no second copy of that code runs (user's choice).
- P2: a `URLProtocol` fixture reads its behaviour from the request's host, never from static state,
  so parallel tests cannot see each other's mode.
- P2: `Task.immediate` orders writes that must be queued before the test goes on; it replaces the
  flag-and-`Task.yield` spins.
- P2: a test waiting on a peer's file watches it with a `DispatchSource` file-system source, never a
  polling loop; its handlers are formed in a `nonisolated` function, or they assert the main actor.
- P2 review: `MCPServerConnection` takes a `searchEnvironment` (default: the process's), so
  `MCPStdioTests` again proves a bare command is looked up on PATH, a case P1 had dropped.
- P2 review: `test_mutable_global` also catches a file-scope `var` behind attributes (`@MainActor var`).
- B1: the user approved pinning the Xcode Test action to English. The Run action follows macOS.
- B1: the user approved returning task handles from `FileSearchSession` and ordering an index
  refresh's visible search before its recents refresh. Tests await completion and use streams to
  control in-flight work.
- B2: a table whose rows pin different parts of one result takes a row type that evaluates its
  query and reads back only the part it pins (`CalcTests.Case`); each test stays
  `#expect(try row.actual() == row.expected)`. A row's environment is data on the row: zones and
  moments as identifiers and ISO strings, resolved with `#require`.
- B2 review: `FileSearchSession` keeps reloading Recent right after an index swap's rerun, on the
  worker, as B1 approved. That review preserved the hand-formatted argument tables.
- B3: the user approved read access to `ClipboardStore.textSearchTask`. The search suite awaits
  the exact requests it starts, including those superseded by a filter change or a hidden palette.
- B3 follow-up: the user requested committing the formatter output for the Calculator, Calendar,
  Clipboard and Emoji suites, including the argument table indentation.
- B4: a suite reads a language's strings from the hosted app's compiled `<code>.lproj`, never the
  source catalog, so it needs no working directory and checks what ships.
- B4: a count tripwire counts argument cases in the result bundle
  (`xcrun xcresulttool get test-results tests`); Swift Testing does not count `#expect` calls.

## Open problems

What a session could not settle. The user answers these; a session never guesses past one.

None.
