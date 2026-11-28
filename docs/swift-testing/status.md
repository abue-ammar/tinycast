# Swift Testing migration: status

Temporary; deleted with [README.md](README.md) in the last commit. Read the brief first.

**Next: P1 · Pilot** (Claude Code, plan mode)

Statuses: `todo`, `next`, `done <commit>`. Exactly one batch is `next`. Numbers are line counts of
the old harness.

## Phases

| Batch | Title                                  | Tool        | Mode  | Rows | Status |
| ----- | -------------------------------------- | ----------- | ----- | ---- | ------ |
| P0    | Docs describe the end state            | Claude Code | build | –    | done   |
| P1    | Pilot: target, host, runner, 4 suites  | Claude Code | plan  | 4    | next   |
| T     | Triage: find what does not belong      | Claude Code | build | –    | todo   |
| R1    | Remove the benchmarks                  | Codex       | build | 8    | todo   |
| R2    | Remove approved candidates             | Codex       | build | –    | todo   |
| B1    | Launcher, search, files                | Codex       | build | 13   | todo   |
| B2    | Calculator, calendar, dictionary       | Codex       | build | 3    | todo   |
| B3    | Clipboard, emoji                       | Codex       | build | 6    | todo   |
| B4    | Palette and design system              | Codex       | build | 10   | todo   |
| B5    | Palette input                          | Codex       | build | 9    | todo   |
| B6    | Dictation, hotkeys, platform           | Codex       | build | 10   | todo   |
| B7    | Window management                      | Codex       | build | 8    | todo   |
| B8    | Commands, links, quick actions         | Codex       | build | 6    | todo   |
| B9    | Notes                                  | Codex       | build | 2    | todo   |
| B10   | Settings, backup, sync, updates        | Codex       | build | 8    | todo   |
| B11   | AI providers                           | Codex       | build | 5    | todo   |
| B12   | AI chat and MCP                        | Codex       | build | 3    | todo   |
| H     | Helper-only sources                    | Claude Code | plan  | 2    | todo   |
| S1    | Stand-ins: small                       | Claude Code | plan  | 6    | todo   |
| S2    | Stand-ins: hotkeys                     | Claude Code | plan  | 2    | todo   |
| S3    | Stand-ins: snippets, dictation field   | Claude Code | plan  | 2    | todo   |
| S4    | Stand-ins: clipboard, custom commands  | Claude Code | plan  | 2    | todo   |
| S5    | Stand-ins: uninstall, quicklinks       | Claude Code | plan  | 2    | todo   |
| S6    | Stand-ins: app installation            | Claude Code | plan  | 1    | todo   |
| F     | Final: clean-up and sign-off           | Claude Code | build | –    | todo   |

Modes are explained in the brief: _plan_ means the session proposes and you approve before it
builds.

## P1 · Pilot

Infrastructure, in this order. Each item is a decision in the brief; this list is the work.

- [ ] `project.yml`: `TinycastTests` (`bundle.unit-test`, sources `Tests/TinycastTests`, depends on
      `Tinycast`, hosted by the Debug app); `PRODUCT_MODULE_NAME: Tinycast` on the app; the `Tinycast`
      scheme's test action runs it. `xcodegen generate`.
- [ ] Test host: `TinycastLaunch.main()` runs a bare `NSApplication` when hosting tests.
- [ ] Signing works for the hosted bundle with the local self-signed identity and with
      `CODE_SIGNING_ALLOWED=NO`; write down whichever the runner needs.
- [ ] `Tests/TinycastTests/Support/`: the fixture-loading and scratch-directory helpers
      `docs/testing.md#writing-a-suite` names.
- [ ] `Scripts/run-tests.sh`: `xcodebuild test` first, then the remaining harnesses; one name runs
      one suite or one harness; `TINYCAST_TEST_*` forwarded as `TEST_RUNNER_TINYCAST_TEST_*`.
- [ ] `Scripts/lint.sh`: the `Model/` purity grep.
- [ ] `Scripts/sync-lsp.sh` and the VS Code build task index the test target (`build-for-testing`);
      `--index` stays until R1 removes it.
- [ ] Xcode's test navigator lists and runs the suites, down to one test.
- [ ] Add SweetPad to `.vscode/extensions.json`'s recommendations. The user confirms it lists and runs
      the suites in VS Code's Testing view; write any setting it needs into `.vscode/settings.json`
      and `docs/development.md#tests-in-the-editor`.
- [ ] Measure one full `./Scripts/run-tests.sh` and write the wall time here.
- [ ] Confirm `docs/testing.md#writing-a-suite` matches what the pilot found; fix it, not the code,
      where they differ.

Suites:

- [ ] PasteSequenceTests · 159 · pure `Model/`
- [ ] FormInputTests · 305 · AppKit on the main actor
- [ ] MCPStdioTests · 172 · fixtures (`Tests/ai-fixtures/mcp-stub.js`)
- [ ] AppleIntelligenceTests · 180 · opt-in `TINYCAST_TEST_APPLE_INTELLIGENCE`

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

## R1 · Remove the benchmarks

Delete the 8 files below, their `run index` lines, `--index` in `run-tests.sh` and `sync-lsp.sh`,
`Scripts/benchmark-dictation.sh`, and every doc line that runs or cites them (`grep -rn
'PerformanceTests\|benchmark-dictation' docs AGENTS.md`). Keep measured numbers in `docs/` that
stand on their own; drop the command that produced them.

- [ ] FileSearchPerformanceTests · 68
- [ ] CalcPerformanceTests · 122
- [ ] ClipboardThumbnailPerformanceTests · 130
- [ ] EmojiSearchPerformanceTests · 96
- [ ] DictationPerformanceTests · 146
- [ ] NotesEditorPerformanceTests · 144
- [ ] TextDiffPerformanceTests · 110
- [ ] ClipboardFilePerformanceTests · 150

## R2 · Remove approved candidates

Delete every **Removal candidates** row marked `approved`: the harness, or the named cases, its `run`
line, and doc lines that cite it. Move rows marked `keep` back to their batch. Candidates found later,
during a batch, are removed in F.

## B1 · Launcher, search, files

- [ ] FuzzTests · 556 · ran at `-O`; check its time at `-Onone`
- [ ] FileSearchTests · 501
- [ ] FileIndexTests · 295
- [ ] FileSearchSessionTests · 247
- [ ] MenuSearchTests · 525
- [ ] WindowSwitchTests · 147
- [ ] RankingTests · 118
- [ ] ScopesTests · 265
- [ ] AppNameTests · 302
- [ ] FavoritesTests · 51
- [ ] LauncherFileTests · 70
- [ ] AppleShortcutTests · 77
- [ ] FallbackTests · 126

## B2 · Calculator, calendar, dictionary

- [ ] CalcTests · 2,887 · mostly tables: `@Test(arguments:)`
- [ ] CalendarTests · 795
- [ ] DictionaryTests · 287

## B3 · Clipboard, emoji

- [ ] ClipboardTests · 1,051
- [ ] ClipboardSyncTests · 219
- [ ] ClipboardThumbnailTests · 226 · a stand-in script plays the helper
- [ ] ClipboardSearchTests · 155
- [ ] EmojiTests · 177
- [ ] EmojiSearchTests · 242

## B4 · Palette and design system

- [ ] PaletteSelectionTests · 420 · its 111,684-assertion count is a tripwire; keep it observable
- [ ] AppearanceTests · 128
- [ ] LanguageTests · 245
- [ ] LocalizedResourceTests · 95
- [ ] InterfaceSizeTests · 365 · also compiles `Extensions/Model/ExtensionFormMetrics.swift`
- [ ] PalettePlacementTests · 386
- [ ] ScrollRevealTests · 77
- [ ] RedactionTests · 71
- [ ] KeyboardFocusTests · 55
- [ ] CalloutTests · 234

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
- [ ] DictationWorkerTests · 270
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

- [ ] AIProviderTests · 2,787 · fixtures; opt-in `TINYCAST_TEST_CODEX_ROOT`
- [ ] PlanUsageTests · 393
- [ ] AIResponsesTests · 378
- [ ] ChatMarkdownTests · 295
- [ ] SyntaxHighlightTests · 369

## B12 · AI chat and MCP

- [ ] AIChatTests · 1,945
- [ ] MCPTests · 326
- [ ] MCPOAuthTests · 632 · fixtures; fixed ports 4962/4963: `.serialized`

## H · Helper-only sources

The app target excludes these sources, so `@testable import Tinycast` cannot reach them. Decide how a
test target compiles them (for example a second, unhosted target that builds the helper sources
itself), record it under Decisions, then convert.

- [ ] ClipboardTextTests · 380 · `ClipboardTextExtractor`, `ClipboardTextHelper`
- [ ] DictationInferenceTests · 146 · `Dictation/Helper`

## S1 · Stand-ins: small

The number is how many app types the harness redeclares.

- [ ] PaletteMenuClickTests · 267 · 3
- [ ] MicrophoneMuteTests · 192 · 1
- [ ] OpenCodeMCPTests · 242 · 1
- [ ] RelaunchTests · 211 · 2
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

- [ ] AppInstallationTests · 643 · 23; opt-in `TINYCAST_TEST_APP_LAUNCH`

## F · Final

- [ ] `run-tests.sh` lists only the harnesses below.
- [ ] Full suite, lint and a Debug build with no new warnings pass.
- [ ] Suites listed and runnable in Xcode's test navigator and, with SweetPad, in VS Code.
- [ ] Removal candidates approved since R2 are deleted.
- [ ] `grep -rn 'harness' docs AGENTS.md CONTRIBUTING.md` shows only the extension harnesses and AI
      CLI harnesses.
- [ ] Delete `docs/swift-testing/` and the pointer in `AGENTS.md`.

## Not migrated

They stay on the old runner and leave the repo with extensions.

ExtensionTests (3,153, with `ExtensionTests+MenuBar` and `ExtensionFetchTests`), ExtensionStoreTests,
ExtensionFormTests (with `ExtensionListKeyTests`), ExtensionAccessoryTests, ExtensionIconTests,
ExtensionCleanupTests, ExtensionRefreshTests, ExtensionMetadataTests, ExtensionVersionTests,
ExtensionSignInTests, ExtensionImageSizeTests, SymbolsTests (`Extensions/Service/SymbolCatalog`),
RaycastTests.

## Removal candidates

One row per candidate. The user writes `approved` or `keep` in the last column.

| Harness or case | Reason (decision 13) | Found in | Answer |
| --------------- | -------------------- | -------- | ------ |

## Decisions log

Decisions made during the migration, beyond the brief's. Newest last.

- (none yet)

## Open problems

What a session could not settle. The user answers these; a session never guesses past one.

- (none)
