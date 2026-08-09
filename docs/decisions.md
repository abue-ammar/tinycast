# Decisions

Choices that were made deliberately and would otherwise look like mistakes worth fixing. Each entry says
what was decided, why, and what would change it.

Add an entry when a choice is non-obvious enough that a competent contributor — or an agent — would
otherwise "correct" it. Do not add one for an ordinary choice with an obvious rationale; this file earns
its keep by staying short enough to read in full.

---

### 1 — `AppCore.shared` is a singleton, not a dependency-injection container

One `@MainActor` singleton owns every long-lived store, monitor, coordinator and window controller, and
`AppDelegate.applicationDidFinishLaunching` calls `AppCore.shared.start()` and nothing else.

**Why:** the app has exactly one of everything and no tests that need to substitute a subsystem — the
harnesses test pure types directly, below this layer. A container would add indirection and a lifecycle
to reason about, in exchange for a seam nothing uses.

**What would change this:** wanting to run two independent instances in one process, or integration tests
that need a fake store.

### 2 — Windows are AppKit, not SwiftUI scenes

`TinycastApp` declares only a `MenuBarExtra`. The palette is a borderless `NSPanel`; Settings and
Onboarding are titled `NSWindow`s, one `AppWindowController` each. The main menu is built by hand too,
replacing SwiftUI's — see entry 32.

**Why:** SwiftUI's `Settings` and `Window` scenes behave unreliably in an accessory (`LSUIElement`) app —
activation, ordering and restoration all misbehave — and the palette needs frame control that a SwiftUI
scene will not give up.

**What would change this:** SwiftUI gaining dependable accessory-app window semantics.

### 3 — Tinycast never uses `NSAlert`

Every confirmation, failure report and value prompt goes through `DialogController`.

**Why:** `NSAlert.runModal` spins a nested run loop, and a held Carbon hotkey fires into it — so alerts
stack without bound. An Aqua alert also clashes visibly with the forced-dark surface. `DialogController`
presents `async`, so nothing blocks the main actor, and it refuses a second dialog while one is up.

**What would change this:** nothing foreseeable. This one is load-bearing.

### 4 — The app is locked to `.darkAqua`

**Why:** the Liquid Glass material and every token in `Theme.swift` are tuned by eye against a deep dark
surface. Light mode is not a switch; it is a second design.

**What would change this:** a deliberate project to design and tune a light surface.

### 5 — There is no XCTest target

The test suite is `Scripts/run-tests.sh`, driving eighteen standalone harnesses.

**Why:** each harness compiles the *shipped* sources it guards, so the pure/effect boundary is enforced by
compilation rather than by convention — a stray `import AppKit` in a `Model/` folder breaks the build of a
test. An XCTest target links the whole app and would lose exactly that property.

**What would change this:** needing to test main-actor UI behaviour, which no harness can reach today —
and even then the pure harnesses should stay.

### 6 — Purity is enforced by the harnesses, not by a lint rule

**Why:** `grep` can catch a forbidden `import`, but only compilation catches the subtler leak — a clock
read, a `FileManager` walk, an `NSScreen` query — because the pure file simply stops building against a
Foundation-only harness. The rule and its enforcement are the same mechanism.

**What would change this:** a build system able to express per-directory dependency rules.

### 7 — `snippetsEnabled` is excluded from settings backups

`SettingsBackupCoverage` names it as a deliberate exclusion, and `settings-backup-test` fails if it is
ever carried.

**Why:** the switch doubles as consent to keystroke listening. An imported backup file must not be able
to turn on a keyboard tap.

**What would change this:** nothing. If the consent and the feature switch are ever separated, the consent
half keeps this exclusion.

### 8 — Consent flags live on the owning store, never in `AppSettings`

`CurrencyRateStore` owns its own consent flag.

**Why:** `SettingsBackup` mirrors `AppSettings`, so a consent flag placed there becomes restorable from a
file — see entry 7. Keeping it on the store makes that structurally impossible rather than merely
forbidden.

**What would change this:** nothing.

### 9 — `SettingsBackup`'s mirror is hand-written, and reflection is not the fix

`AppSettingsKey` lists every persisted key; `SettingsBackupCoverage` says which are carried and which are
excluded, with a reason. `settings-backup-test` fails when a key is neither.

**Why:** a `Mirror`, macro or codegen scheme would silently auto-include the *next* consent flag someone
adds and make it backup-restorable. The duplication is the safety mechanism: adding a setting forces an
explicit decision about whether it belongs in a backup.

**What would change this:** nothing, while any consent flag is expressible as a setting.

### 10 — Networked features ship off, gated, and on a cacheless session

Every network-touching feature defaults to off behind a Settings toggle whose dialog names the provider,
the cadence and what leaves the machine. Fetches use a private `.ephemeral` `URLSession` with
`urlCache = nil`, and consent is re-checked on both sides of the `await`.

**Why:** offline-by-default is the product promise. `URLSession.shared` would leave a second copy of the
response in the on-disk `URLCache` that opting out does not delete, and consent can be withdrawn while a
request is in flight.

**What would change this:** nothing. `CurrencyRateStore` is the reference implementation; copy it rather
than inventing a second shape.

### 11 — The safe state is the default, structurally

`CalcEngine.evaluate`'s `currency:` parameter defaults to `.off`.

**Why:** forgetting to pass a consented source disables the feature instead of enabling it. A gate you can
forget to close is not a gate.

**What would change this:** nothing; apply the same shape to any new gated capability.

### 12 — Uninstall trashes, and never deletes

`FileManager.trashItem` is the only removal call in the feature; `removeItem` appears nowhere in it.

**Why:** it is what makes display-name attribution tolerable. Leftover files are matched partly by the
app's display name, which will occasionally be wrong — and a false positive costs the user a drag back out
of the Trash rather than their data.

**What would change this:** a "delete permanently" option would have to drop name matching in the same
commit.

### 13 — Uninstall detects Full Disk Access and never requests it

`UninstallScanner` probes silently. The feature asks for no permission at all.

**Why:** a file-removal feature that escalates its own privileges is a different, worse feature. Scanning
less is the correct behaviour when access is absent.

**What would change this:** nothing.

### 14 — `QuicklinkStore` reports a database it cannot open; `ClipboardStore` discards one

**Why:** clipboard history is regenerable — deleting and recreating a corrupt database costs the user
nothing they cannot reproduce by copying again. A quicklink library is authored data, and losing it
silently is unacceptable. The two stores differ because the data differs, not by oversight.

**What would change this:** quicklinks gaining a durable backup elsewhere.

### 15 — There is one template engine

Quicklinks expand through `SnippetTemplateEngine` rather than a second parser.

**Why:** one engine is what makes `| raw` mean something — it opts a value out of the automatic
percent-encoding a URL destination asks for. Two parsers would drift on exactly this kind of detail.

**What would change this:** a destination type whose escaping rules genuinely cannot be expressed as a
filter.

### 16 — Searchable fields stay separate, and the band arithmetic is not tuned

Display name, Spotlight alternate names, bundle id and executable name are scored as distinct fields, never
flattened into one string.

**Why:** the field is what picks the relevance band, and the bands are spaced an order of magnitude above
`FuzzyMatch.maximumScore` and two above the learned-ranking boost cap. That spacing is what keeps a learned
boost reordering results *within* a tier and never across one. Flattening the fields, or narrowing the
spacing, silently breaks both properties. The scorer is fuzz-tested over ~100k random queries.

**What would change this:** a new searchable field means a new `Band` case and a `consider` call in
priority order — not a change to the arithmetic.

### 17 — No full-text index for the launcher, no icon prewarming, no extra caches

**Why:** roughly 350 entries scored linearly behind a one-deep memo is already well inside frame budget; an
index would cost RAM and startup time for no perceptible gain. Prewarming the icon cache would trade the
thing the app protects most — launch — for a benefit users already do not perceive, since `AppIconView`
seeds warm icons synchronously.

**What would change this:** a measurement showing the search or first paint outside budget.

### 18 — One actor, and no custom actors

Almost everything is `@MainActor`; heavy work is `nonisolated` plus `Task.detached`.

**Why:** a second actor would add hops on the palette's hot path and buy nothing. The state involved —
windows, pasteboard, event taps — is main-actor-owned by nature, and the CPU-bound work is already off-main
as pure static functions.

**What would change this:** genuinely concurrent mutable state that is not UI-adjacent.

### 19 — `ClipboardStore` and `QuicklinkStore` each carry their own SQLite helpers

**Why:** the two stores must stay independently compilable by their own harnesses, and that isolation is
worth about sixty duplicated lines. A shared helper would couple them and pull one of them out of its
harness.

**What would change this:** a third SQLite store, at which point a Foundation-only shared helper compiled
into all three harnesses becomes the better trade.

### 20 — An intended default is not backward compatibility

Nine properties in `AppSettings` read as
`defaults.object(forKey: Key.x) == nil || defaults.bool(forKey: Key.x)`.

**Why:** this is not legacy support. `defaults.bool(forKey:)` returns `false` for an absent key, and these
settings must start **on** for a fresh install. Simplifying it changes the fresh-install default, which is
a UX change. The same applies to `ClipboardRetention`'s `-1`-means-forever, `PopToRootTimeout`'s
`0`-means-immediately, and `windowGap`'s unset-reads-as-zero.

**What would change this:** you may rename these keys freely; you may not change what a fresh install
starts with without deciding to.

### 21 — External formats are not legacy code

Raycast `.rayconfig` (v1 and v2) and the snippet Markdown files are formats Tinycast does not own.

**Why:** compatibility with *another* application's format, or with a file the user edits by hand, is not
backward compatibility with a previous Tinycast, and the "delete legacy code" posture does not apply to it.
Tinycast's own export formats — `SettingsBackup` and `QuicklinkArchive` JSON — *are* internal and may
change freely, provided export → import round-trips within one build.

**What would change this:** Raycast retiring a format, or the snippet format gaining a versioned migration.

### 22 — The two Raycast import formats share no mapper

`RaycastFormat.detect` is the only branch between them; neither is tried as a fallback for the other.

**Why:** a fallback is what turns "wrong passphrase" into "not a Raycast export". Keeping the decrypt and
field mapping separate per format is what lets each report its own real failure.

**What would change this:** nothing.

### 23 — Within one build, the reader and the writer must agree

Rename anything, but not by halves:

- `SettingsKey.showInMenuBar` is shared between `AppSettings` and `TinycastApp`'s `@AppStorage`
- `AppEntry.id` values, including the `quicklink:` / `custom-command:` / `window-command:` prefixes, are
  the keys for favourites, visibility and learned ranking
- `ClipboardManager.internalType` marks Tinycast's own pasteboard writes so the poller skips them — if the
  writer and the poller disagree, the app re-captures its own pastes in a loop
- SQLite column names must match across the schema, the prepared statements and the row decoder

### 24 — Compatibility: no migrations, except two that are scheduled

Tinycast carries no version flags and no migration layer, with two exceptions that exist because `v0.7.5`
is a shipped stable release and both would otherwise have destroyed real user data on update:

| What | Migration |
| --- | --- |
| `hotkey.<action>` keys and `HotKeyBinding`'s synthesised `Codable` | `LegacyHotKeyRecords.adopt`, called once from `HotKeyManager.start()` — `v0.7.5` stored a bare `{"carbonKeyCode":N,"carbonModifiers":N}` under `KeyboardShortcuts_<name>`, so every shipped binding would have read as unbound |
| `ClipboardStore`'s `source_app` / `pinned_at` columns | the two `ALTER TABLE` guards and `columnExists` — `v0.7.5` has no `pinned_at`, the prepared statements would fail, and the store deletes a database it cannot open |

**Delete both** once the release carrying them is two further stable releases old, so no supported upgrade
path still starts from `v0.7.5`. Each removal is a pure deletion: `LegacyHotKeyRecords.swift` plus its one
call site, and the two guards plus `columnExists`. Neither carries a version flag or persisted state, so
nothing is left behind. Until then, `grep -rn "ALTER TABLE\|columnExists" Tinycast` returning three hits is
expected.

**Nothing new may depend on either.**

### 25 — XcodeGen owns the project; there is no SwiftPM manifest

`Tinycast.xcodeproj` is committed but generated from `project.yml`.

**Why:** the app needs Xcode build settings SwiftPM cannot express, and committing the generated project
keeps `xcodebuild` and the IDE working without a generation step for anyone just building. `project.yml`
stays the source of truth so settings changes are reviewable as text.

**What would change this:** nothing while the app is an app rather than a library. Note that
`Bundle.module` must never be used for shipped resources.

### 26 — There is a linter, and deliberately no formatter

SwiftLint runs (`./Scripts/lint.sh`). Formatting is whatever Xcode's re-indent does, as before.

**Why:** both candidates were adopted, configured and measured on this tree, and both wanted to change
code rather than lay it out.

`swift-format`, which ships in the Xcode toolchain and is what sourcekit-lsp uses, rewrote `track({`
onto two lines, split function signatures, moved `{` onto its own line after wrapped conditions, and
added trailing commas SwiftLint then flagged. None of it was tunable: it changed exactly 74 files at
`lineLength` 120 and at 1000.

SwiftFormat is configurable enough to leave structure alone — but only after disabling eight rules, and
one of the rules left on introduced a **semantic** error. `--enable isEmpty` rewrote `$0.count > 0` to
`!$0.isEmpty` in `LauncherRankingStore` and `PaletteRowIndex`, whose `count` is a hit count and not a
collection count. Two harnesses stopped compiling. `numberFormatting` also silently stripped the digit
separators from `3_000` and `9_007_199_254_740_992`.

That is the same class of failure as the original incident behind this entry — VS Code's format-on-save
reflowing five sites in `WindowLayout.swift` — and it is what a formatter is for: rewriting code nobody
asked it to touch. A codebase this size, with one regular contributor and a consistent hand-tuned
style, does not get enough back to justify it. SwiftLint gives the defect-catching half with none of
the rewriting.

For the same reason SwiftLint's `empty_count` rule is **disabled**: it flags the identical two lines.

**What would change this:** several regular contributors, at which point re-run this experiment — but
keep `isEmpty`/`empty_count` off, and verify against the harnesses before committing the result.

**Amended:** format-on-save is now **on** in `.vscode/settings.json`, by explicit request, with a
`.swift-format` at the repo root tuning `swift-format` to this tree — 4-space indent, `lineLength` 110,
`respectsExistingLineBreaks`, trailing commas off, and the rules that rewrite rather than lay out
disabled. That cuts the blast radius from **200 files of 200** at stock settings (which default to
2-space indent) to **58**. It does not cut it to zero, and the objection above still stands for those
58 — this entry is the record of what a formatter costs here, not a claim that one is now safe.
`EmojiData.generated.swift` is the sharpest edge: saving it rewrites ~4 000 lines, and generated files
are never hand-edited. Have `Scripts/gen-emoji.js` emit `// swift-format-ignore-file` before relying on
it.

### 26a — The comment policy is not linted

The 100-character cap and the ban on stacked comment lines live in
[standards.md](standards.md#comments) and [AGENTS.md](../AGENTS.md) only. They were `custom_rules` in
`.swiftlint.yml` for a while; the rules were removed and the policy kept.

**Why:** a linter reports a comment after it has been written, so the cost of a violation is a second
edit rather than a better first one — and as warnings they never blocked anything, which made them
scenery. What actually drove the drift they were meant to catch was the code itself: thirty-two stacked
comments in the tree taught every reader, human or agent, that stacking was the house style, and no
amount of restating the rule outweighed that. Cleaning those out fixed it; the rules had not.

**What would change this:** stacked comments returning at a rate that a manual read does not catch. The
fix then is still to delete the counter-examples first — reach for a rule only if that stops working.

### 27 — Zero third-party dependencies

**Why:** every dependency is a supply-chain surface, a signing complication and a reason the app cannot be
built from a clean checkout. Nothing so far has been worth it — the vendored `KeyboardShortcuts` library
was removed in favour of an in-house Carbon hotkey stack, which also fixed behaviour it could not express.

**What would change this:** a genuinely hard problem with a well-audited, small, stable solution.

### 28 — `EdgeDissolve.swift` and `ThinScrollbar.swift` are off-limits

Both are exempt from the comment budget and from edits.

**Why:** both are tuned by eye against the palette's floating bars, so any change is a visual regression
until proven otherwise. Needing to touch one to fix a scroll bug is the signal that the real fix belongs
elsewhere — a scroll target, an inset, an intent.

**What would change this:** an explicit task to change that look.

### 29 — `AppIndex.refresh` collapses trailing refreshes rather than cancelling and restarting

**Why:** a burst of change notifications should produce one scan at the end, not a cancelled scan per
notification. Cancel-and-restart starves the scan under a sustained burst.

**What would change this:** nothing observed.

### 30 — No privacy manifest, and no localization scaffolding

**Why:** a privacy manifest describes third-party SDKs and tracking; Tinycast has neither (entry 27). And
the app is single-locale by design — the calculator's natural-language date and currency grammars are
English-specific, so localizing the UI without them would ship a half-translated product.

**What would change this:** shipping through a channel that requires a manifest, or a decision to localize
the calculator grammars first.

### 31 — Toggling Include Shift rewrites a chord the user may have typed by hand

Flipping Include Shift re-points every stored combo whose modifiers contain the other Hyper chord. A combo
recorded by physically holding ⌃⌥⌘ is byte-identical to one recorded from ✦, so it is re-pointed too — a
hand-typed ⌃⌥⌘G becomes ⌃⌥⇧⌘G.

**Why:** provenance is not recoverable. The tap rewrites flags before anything sees them, so the recorder
cannot tell a real ⌃⌥⌘ from a synthesized one, and storing a "recorded from Hyper" bit would mean trusting
a heuristic at capture time forever. Leaving the chord alone is the worse failure: the keycaps stop saying
✦ *and* the shortcut stops firing, because Carbon stays registered for a chord the tap no longer emits.
Re-pointing keeps what the keycaps say and what actually fires in agreement, which is the property users
notice. See [hotkeys.md](features/hotkeys.md#include-shift-re-points-what-is-already-recorded).

**What would change this:** a way to know at capture time that the flags came from the tap — the tap would
have to mark its rewritten events in a field `NSEvent` still exposes.

### 32 — Settings and the palette are two lifecycles, and ⌘Q closes a window

The palette and Settings share no window ownership. Hiding the palette never closes, hides or reorders
Settings; closing Settings never touches the palette. Neither coordinator can reach the other's surface —
`PaletteCoordinator` holds no `AppCore` back-reference at all, which is what makes that checkable.

Two consequences look wrong out of context:

- **⌘Q is "Close Settings", not Quit**, and the app menu carries no Quit item at all. Quitting stays on
  the menu-bar extra and the launcher's Quit Tinycast command. The menu-bar extra's Quit button
  deliberately carries no ⌘Q either — two contradictory ⌘Qs is worse than none.
- **The menu is declared with `.commands`, never assigned to `NSApp.mainMenu`.** SwiftUI's default menu
  carries a real `Quit ⌘Q`, so with Settings focused — or even with just the palette up — ⌘Q terminated
  the background agent. An imperative `NSApp.mainMenu = …` install *looks* like it fixes that and does
  not: **SwiftUI rebuilds the menu on any scene change, and toggling Show in Menu Bar is one**, silently
  restoring its own Quit. Only a `CommandGroup` survives, because it is the scene definition rather than
  something racing it.

**Why:** Tinycast is an agent that happens to have a settings window, not a windowed app. Every reflex
that closes a window — ⌘Q, ⌘W, the red traffic light, the last window closing — has to leave the hotkeys,
the clipboard poller and the snippet listener running, or the app silently stops being itself.
`applicationShouldTerminateAfterLastWindowClosed` returns `false` for the same reason.

**What would change this:** Tinycast growing a document surface, where ⌘Q meaning Quit would matter more
than an agent surviving a closed window.
