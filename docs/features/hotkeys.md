# Hotkeys (in-house, zero dependencies)

`Features/HotKeys/` holds:

- `KeyShortcut` — Sendable model, Carbon keycode + modifiers, layout-aware glyphs via `UCKeyTranslate`.
- `HotKeyBinding` — what an action is actually bound to: a `.combo(KeyShortcut)` or a
  `.doubleTap(DoubleTapModifier)`.
- `HotKeyCenter` — the Carbon `RegisterEventHotKey` layer, pausable.
- `DoubleTapModifier` / `DoubleTapDetector` / `DoubleTapMonitor` — the double-tap stack.

`HotKeyManager` owns them all: persistence, conflict lookup, and dispatch. Every action reads and
writes one `HotKeyBinding`, so the two kinds share persistence, conflict detection, the recorder and
the keycap rendering — only the _engine_ differs.

## Invariants

- **Hotkeys persist as JSON strings under `hotkey.<action>` UserDefaults keys**, and
  `HotKeyAction.defaultsKey` is the one place that computes a key — it is also the `HotKeyCenter`
  registration id, so the two cannot drift.
- **`HotKeyBinding` is the one thing an action is bound to, and it has two cases with two engines.** A
  `.combo` is a Carbon registration; a `.doubleTap` is recognized by `DoubleTapMonitor`, because Carbon
  cannot see a lone modifier at all. Its `Codable` is the synthesised one.
- `KeyShortcut`'s hand-written `init(from:)` is a correctness seam, not a format one: it routes every
  decode through the initializer that masks device modifier bits off.
- **`Model/DoubleTapModifier.swift` and `Model/DoubleTapDetector.swift` stay Foundation-only and pure**
  with the clock injected as a parameter, for `hotkey-test`. Every `CGEvent` call lives in
  `Service/DoubleTapMonitor.swift`, which is listen-only, installs *only* while something is bound to a
  double-tap, and never prompts for Accessibility.
- **`KeyShortcut.hyperChord(includesShift:)` is the only spelling of the Hyper chord**, read by both the
  ✦ collapse and the re-point below. `HyperKeyTap` composes its own flags because it also needs the
  left-side device bits, which no display path wants.
- `LegacyHotKeyRecords` is scheduled for deletion and nothing new may depend on it.

## Persistence

Bindings persist as JSON strings under `hotkey.<action>` UserDefaults keys, computed in one place —
`HotKeyAction.defaultsKey`, which doubles as the `HotKeyCenter` registration id. The set of bound
bundle IDs lives in `boundAppBundleIDs` and is re-registered on launch. System Settings panes use
`boundPaneBundleIDs`; custom commands and quicklinks use their stable UUIDs in
`boundCustomCommandIDs` and `boundQuicklinkIDs`. Those two are the per-item case — unlike a fixed
catalog, there is no `allCases` to walk — so each needs an index for `start()` to re-register from
and to prune bindings whose record was deleted while Tinycast wasn't running. That prune is why
`QuicklinkStore` loads at launch even when the feature is off
(see [quicklinks.md](quicklinks.md#hotkeys)).

`HotKeyBinding` takes the synthesised `Codable`, so a `.combo` writes
`{"combo":{"_0":{"carbonKeyCode":N,"carbonModifiers":N}}}` and a `.doubleTap` writes
`{"doubleTap":{"_0":"command"}}`. `KeyShortcut` keeps a hand-written `init(from:)` — not a format seam,
but the guarantee that every decode runs through the initializer that masks device modifier bits off.
`SettingsBackup.HotkeyBackup` stores the same values, so the backup file carries this shape too; only
export → import within one build is guaranteed to round-trip.

`LegacyHotKeyRecords` adopts the records shipped before this namespace existed — `v0.7.5` wrote a bare
`{"carbonKeyCode":N,"carbonModifiers":N}` under `KeyboardShortcuts_<name>`. It runs once from
`start()`, consumes each old record, and never overwrites a key the user has already rebound. Its
`legacyKey` returns nil for an action that postdates the scheme, so nothing new has to invent a
migration key it never wrote. It is scheduled for deletion.

`hotkey.searchFiles`, `hotkey.toggleClipboard`, `hotkey.toggleEmoji`, `hotkey.showNotes`,
`hotkey.createNote` and `hotkey.searchNotes` are the built-in launcher commands with an action of their
own, alongside `hotkey.togglePalette`, which has no command row. They are the only `CommandID`s whose
`hotKeyAction` is non-nil — which is what puts a recorder on their rows in Settings ▸ Commands, and a
keycap on their launcher rows. Each is also reachable from its own feature pane, so it is one binding
from two places, not two settings. `HotKeyManager` names them all through `CommandID`, so a conflict
callout spells an action exactly as its command row does.

Like a window command, the chord registers regardless of the launcher row. Search Files and Notes both
re-check their feature switches before opening; see [file-search.md](file-search.md#invocation) and
[notes.md](notes.md#ownership-and-enablement). A hidden launcher row does not disable its shortcut, but
disabling the feature does. `SettingsBackup.HotkeyBackup` carries every fixed feature binding. They
return nil from `LegacyHotKeyRecords.legacyKey` because they postdate the old scheme and must never
invent migration records.

System actions and window commands are the fixed-catalog case: they persist under
`hotkey.systemAction.<raw-id>` and `hotkey.windowCommand.<raw-id>`
and need **no** bound-ID index, because `start()` and `conflictOwner` can just iterate `allCases` and
`register` no-ops on an unbound item. A registered window-command shortcut still runs nothing while the
feature switch is off — `WindowCommandCoordinator.runWindowCommand` re-checks it (see
[window-management.md](window-management.md)); a system-action shortcut likewise goes through
`SystemActionCoordinator.runSystemAction(id:)`, so the confirmation gate holds for a hotkey exactly as it does for the
palette.

## Double-tap modifiers

Any action can instead be bound to a **double-tapped lone modifier** — ⌃, ⌥, ⇧ or ⌘. Carbon cannot
register a modifier-only shortcut at all, so this is a separate engine that meets the combo path only
at `HotKeyBinding`.

`DoubleTapDetector` is the recognizer: Foundation-only, pure, and clock-injected (`now` is a caller-
supplied monotonic timestamp), so `Tests/hotkey-test.swift` drives it without an event tap. A **tap**
is a press that starts from no modifiers held, keeps exactly one of the four held with no `fn`
alongside, sees no key press or mouse click, and is released within `maxHold` (250 ms — the same
window `HyperKeyTap` calls a quick press). A **double-tap** is a second tap of the same modifier
starting within `maxGap` (300 ms) of the first one's release.

Only _momentary_ keys may feed `hasOtherModifiers`. Caps Lock must not: `maskAlphaShift` tracks the
**latch**, not a press, so testing it would disqualify every tap for as long as Caps Lock is on and
silently kill the feature. Caps Lock is still ineligible as a _binding_ — that is what the Hyper Key
is for.

It **fires on the second release, not the second press**. The modifier is then already up when the
action runs, so the palette never opens with a phantom ⌘ held and focus restoration isn't polluted —
and "double-tap and hold" is a deliberate non-event.

`DoubleTapMonitor` is the one platform file. It is a **listen-only** `CGEventTap` and it installs only
while something is actually bound to a double-tap, so users who never use the feature pay nothing. Two
details are load-bearing:

- It is `.tailAppendEventTap`, unlike the two head-inserted taps, so it observes events **after**
  `HyperKeyTap`'s rewrite. A Hyper-remapped right-side modifier therefore arrives as the full ⌃⌥⇧⌘
  chord and correctly reads as "not a lone modifier" — the left-side twin still double-taps.
- Like every keyboard tap it needs the **Accessibility** grant, and it never prompts for it. The
  binding records regardless; the recorder shows an inline warning that opens System Settings, and the
  one-second health timer installs the tap the moment the grant lands.

⇧ is bindable this way even though `KeyShortcut` rejects a bare ⇧ combo: a double-_tap_ is unambiguous
where a bare ⇧ combo would shadow typing.

## The Hyper Key

`HyperKeyTap` turns one physical key — Caps Lock or a right-side modifier — into the ⌃⌥(⇧)⌘ chord
system-wide. It is a **modifying** `CGEventTap`, a separate layer from `HotKeyCenter` because Carbon
cannot intercept a lone key at all. The rewritten flags flow onward into Carbon matching, so existing
combo hotkeys fire from Hyper+key with no extra registration.

Which key is chosen persists as a `HyperKey` string raw value in `AppSettings` — renaming a case is a
migration, and a removed case decodes to `.none`. **F-keys are deliberately not candidates:** the
top-row media functions fire *below* the tap, so binding F1 as Hyper still dimmed the display.

### Caps Lock has to stop being Caps Lock

The caps-lock toggle — both the LED and the latch — happens below every `CGEventTap`, so no tap can
suppress it. The key must therefore stop being Caps Lock **at the source**: while Caps Lock serves as
Hyper, `CapsLockRemap` installs an IOKit `UserKeyMapping` remapping it to **F18**, the same mechanism
`hidutil` uses. The tap then intercepts F18 in its place. The remap is cleared on unbind and on quit,
and never survives a reboot. Remaps apply on a serial queue, so rapid on→off→on toggles land in call
order instead of racing as independent detached tasks and leaving the wrong final state.

Because the remap is asynchronous, there is a fallback for the window before it takes hold: the key
still arrives as Caps Lock, so the tap rides the modifier path instead. The LED toggles during that
window — that is un-remapped HID behaviour, not something Tinycast can stop.

Once remapped, Caps Lock arrives as **keyDown/keyUp** rather than `flagsChanged`. Both ends are
converted into Left Control `flagsChanged` transitions, so everything downstream sees the Hyper chord
move with the key rather than a swallowed press. A classic `IOHIDSystem` connection reads and drives
the Caps Lock LED and lock state; it is used only by the explicit Quick Press toggle and the one-time
unlatch when the remap is installed.

### Press tracking uses toggle semantics

`flagsChanged` does not describe its own direction, so a modifier-style Hyper key is tracked by
toggling. The obvious alternative — querying `CGEventSource` key state — **races the release**,
inverting the state machine and breaking Quick Press. A missed release therefore lingers only until
the watchdog or the next press clears it. Work that posts events or touches IOKit is deferred to the
next runloop turn rather than run inside the tap callback, where it would risk re-entrancy.

The flags OR'd into every rewritten event are the generic ⌃⌥(⇧)⌘ masks **plus the left-side device
bits** (`NX_DEVICE…KEYMASK`, from `IOLLEvent.h`). Some consumers distinguish sides, and generic-only
flags do not always read as fully pressed. The Hyper key's own residue is scrubbed in the same pass:
Caps Lock's alpha-shift bit, or — for a key modifier outside the Hyper set — its generic mask and both
device bits. Events the tap posts carry a `"TYCT"` marker in `.eventSourceUserData`, the same FourCC
`HotKeyCenter` uses, so the tap never reacts to its own synthetics.

### ✦ is the notation, not a preference

Any combo whose modifiers are a superset of the chord renders with the Hyper set replaced by a single
**✦** keycap — `✦G`, or `✦⇧G` when a modifier survives the subtraction. It is unconditional: there is
no toggle, because collapsing the chord is what the feature *is*. The one condition is a Hyper key
being configured at all — `AppCore` hands `KeyShortcut.displayedHyperChord` a `nil` chord otherwise, and a
literal ⌃⌥⌘G renders as itself. That hook is a **closure rather than a value** so reading it inside a
view body registers the `AppSettings` dependency, and every keycap re-renders the moment a toggle moves.

### Include Shift re-points what is already recorded

A `KeyShortcut` stores absolute Carbon modifiers, captured from the already-rewritten flags, so a chord
recorded under one Include Shift setting is stale under the other: it would stop collapsing to ✦ *and*
stop firing, because Carbon is registered for ⌃⌥⌘ while the tap has started emitting ⌃⌥⇧⌘. So flipping
the toggle re-points every stored combo — `HotKeyManager.retargetHyperBindings`, driven by the same
`AppCore.track` observation the feature switches use, swapping the stale chord for the current one
through `setBinding` so persistence and re-registration stay on one path. A re-point that would land on
a chord another action already holds is skipped rather than clobbering it; that row keeps its literal
keycaps. `retargetingHyper` is idempotent, which is what makes a settings import a no-op rather than a
corruption. Nothing is re-pointed while the Hyper key is `.none` — and the Settings row is disabled
there, so the toggle cannot move without a chord to mean.

### Lifecycle

Like every keyboard tap it needs the **Accessibility** grant and never prompts for it. A one-second
watchdog runs while a key is configured: it retries installation until the grant lands, notices
revocation, revives a tap the system disabled on timeout or user input, and clears a stuck hold. On
fast user switching another session owns the keyboard, so half-held state is dropped and rewriting
stops until this session is active again. The HID remap outlives the process, so
`applicationWillTerminate` hands the key back to the system before exiting.

## Recorder

The settings recorder (`Features/HotKeys/UI/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyManager.recordingAction` state, and keys are captured by local
NSEvent monitors while both engines are paused. It records both kinds — type a combo, or double-tap a
modifier — by feeding its `.flagsChanged` / `.keyDown` monitors into the _same_ `DoubleTapDetector`
the global monitor uses, so recording needs no event tap and no permission.

Setting `recordingAction` is what starts and stops the capture, so there is exactly **one**
`ShortcutCaptureSession` (`HotKeys/Service/`) for the app rather than one per row — which is what lets the
callout above the field render the live state from outside the row that opened it. The field itself
only ever shows the binding; the prompt, the live preview and the conflict message all live in the
callout. See [ui.md](../ui.md#the-shortcut-recorder-callout).
