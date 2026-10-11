# Hotkeys (in-house, zero dependencies)

`Features/HotKeys/` holds:

- `KeyShortcut` — Sendable model, Carbon keycode + modifiers, layout-aware glyphs via `UCKeyTranslate`.
- `HotKeyBinding` — what an action is bound to: `.combo(KeyShortcut)`,
  `.doubleTap(DoubleTapModifier)`, sided `.modifier` / `.doubleModifier`, `.globe`, or `.doubleGlobe`.
- `HotKeyCenter` — the Carbon `RegisterEventHotKey` layer, pausable.
- Dictation alone also observes Carbon's key-release event for hold-to-talk.
- `DoubleTapModifier` / `DoubleTapDetector` — the double-tap recognizer.
- `ModifierKey` / `ModifierKeyDetector` — reported sides, lone presses, taps and holds.
- `ModifierTapMonitor` — the shared modifier-only tap, including Dictation's hold/release callbacks.

`HotKeyManager` owns them all: persistence, conflict lookup, and dispatch. Every action reads and
writes one `HotKeyBinding`, so all cases share persistence, conflict detection, the recorder and
the keycap rendering — only the _engine_ differs.

Carbon's dispatcher enters through an explicit `@MainActor` callback. Press and release handlers
return `OSStatus` synchronously, preserving event order and hold-to-talk release handling.

## Invariants

- **Hotkeys persist as JSON strings under `hotkey.<action>` UserDefaults keys**, and
  `HotKeyAction.defaultsKey` is the one place that computes a key — it is also the `HotKeyCenter`
  registration id, so the two cannot drift.
- **A command's shortcut and its launcher row run the same funnel.** `HotKeyAction.command(CommandID)`
  is parameterised over the whole catalog and dispatches through `LauncherCoordinator.runCommand`, so a
  new built-in command arrives bindable with no hotkey plumbing of its own, and there is one behaviour
  per command rather than one per invocation route.
- **A command that opens a palette mode toggles it.** Every one of them enters through
  `PaletteCoordinator.togglePalette(mode:)`, so a second press closes what the first opened. From a
  launcher row the palette is in `.launcher`, so the row always re-points instead.
- **`HotKeyBinding` is the one thing an action is bound to, with two engines.** A
  `.combo` is a Carbon registration; all modifier-only bindings are recognized by
  `ModifierTapMonitor`, because Carbon cannot see a lone modifier at all. Its `Codable` is the
  synthesised one.
- `KeyShortcut`'s hand-written `init(from:)` is a correctness seam, not a format one: it routes every
  decode through the initializer that masks device modifier bits off.
- **The modifier-only detectors stay Foundation-only and pure** for `hotkey-test`, with the clock
  injected as a parameter. Every `CGEvent` call lives in
  `Service/ModifierTapMonitor.swift`, which is listen-only, installs *only* while a modifier-only
  shortcut is bound, and never prompts for Accessibility.
- **`KeyShortcut.hyperChord(includesShift:)` is the only spelling of the Hyper chord**, read by both the
  ✦ collapse and the re-point below. `HyperKeyTap` composes its own flags because it also needs the
  left-side device bits, which no display path wants.
- **The private HID SPI lives in `Platform/HIDEventSystem.swift` alone**, resolved at runtime, so a
  macOS without it degrades the Hyper Key to `.remapUnavailable` instead of crashing.
- **`KeyboardRemapper` only ever removes the Hyper Key's own entries** (`HIDKeyMapping.hyperKeyMappings`),
  so another tool's mapping for another key always survives Tinycast turning the Hyper Key off.
- **A raw Caps Lock is never read as Hyper.** Its latch carries no release, so treating one as a press
  leaves the chord on every keystroke until the next press.

## Persistence

Bindings persist as JSON strings under `hotkey.<action>` UserDefaults keys, computed in one place —
`HotKeyAction.defaultsKey`, which doubles as the `HotKeyCenter` registration id. The set of bound
bundle IDs lives in `boundAppBundleIDs` and is re-registered on launch. After every `AppIndex` scan,
`HotKeyManager.removeAppBindings` clears the binding of an app that is gone from both the index and
LaunchServices: its Settings row went with it, so nothing else could clear the chord. Requiring both
keeps a dropped search scope from deleting a working shortcut, and running on unchanged scans too
covers LaunchServices still resolving an app for a few seconds after it is trashed.

Shortcuts are also spelled as typeable chords (`ctrl+option+left`) in the opt-in
[settings file](settings-file.md) — all but those of content, extensions and Apple Shortcuts.
`HotKeySpelling` is that grammar; `HotKeySettingsFile` applies through `setBinding`, so `UserDefaults`
stays the one store either way.

System Settings panes use `boundPaneBundleIDs`; custom commands, quicklinks, window layouts, rooms
and custom window sizes use their stable UUIDs in `boundCustomCommandIDs`, `boundQuicklinkIDs`,
`boundWindowLayoutIDs`, `boundWindowRoomIDs` and `boundCustomWindowSizeIDs`. Those five are the per-item case — unlike a fixed catalog, there is no `allCases` to walk — so each needs an index for `start()`
to re-register from
and to prune bindings whose record was deleted while Tinycast wasn't running. That prune is why
`QuicklinkStore` loads at launch even when the feature is off
(see [quicklinks.md](quicklinks.md#hotkeys)).
Apple Shortcuts keep the same kind of index in `boundAppleShortcutIDs`, pruned not at launch but after
the first successful read of the library, since a failed read looks exactly like deletion
(see [apple-shortcuts.md](apple-shortcuts.md#sweeping-deleted-shortcuts)).

Snippets index `StoredSnippet.ID`, the file's path, in `boundSnippetIDs`. The store runs only while
the feature is on, so they are swept not at launch but on every snapshot, by
`removeSnippetBindings`; a file that fails to parse still counts, since it is mid-edit rather than
gone. A rename outside Tinycast or a new Snippets Folder therefore drops the shortcut, and none
travels in a backup, where an imported snippet lands at a new path
(see [snippets.md](snippets.md#shortcuts)).

`HotKeyBinding` takes the synthesised `Codable`, so a `.combo` writes
`{"combo":{"_0":{"carbonKeyCode":N,"carbonModifiers":N}}}` and a `.doubleTap` writes
`{"doubleTap":{"_0":"command"}}`. `KeyShortcut` keeps a hand-written `init(from:)` — not a format seam,
but the guarantee that every decode runs through the initializer that masks device modifier bits off.
`SettingsBackup.HotkeyBackup` stores the same values, so the backup file carries this shape too; only
export → import within one build is guaranteed to round-trip.

Every built-in command is bindable: `CommandID.hotKeyAction` answers `.command(self)` by default, and
names the three exceptions. Open in Browser and Run Shell Command are query-driven — their input is the
typed text a chord has none of — and Quit is withheld so no chord can terminate the app outright. The
list is a deny-list rather than an allow-list, so a new command still arrives bindable without an edit
there. A binding therefore persists under `hotkey.<command raw value>`, as in
`hotkey.command:clipboard-history`, which is also what puts a recorder on the command's row and a
keycap on every launcher row. That row is in exactly one pane — Settings ▸ Commands, or the feature's
own pane when `SettingsTab.ownedCommands` names it. `hotkey.togglePalette` is the one fixed action with
no command row. `HotKeyManager` names them all through `CommandID`, so a conflict callout spells an
action exactly as its command row does.

Like a window command, the chord registers regardless of the launcher row. Search Files and Notes both
re-check their feature switches before opening; see [file-search.md](file-search.md#invocation) and
[notes.md](notes.md#ownership-and-enablement). A hidden launcher row does not disable its shortcut, but
disabling the feature does. `SettingsBackup.HotkeyBackup` carries them as one `commands` map keyed by
`CommandID` raw value.

System actions and window commands are the fixed-catalog case: they persist under
`hotkey.systemAction.<raw-id>` and `hotkey.windowCommand.<raw-id>`
and need **no** bound-ID index, because `start()` and `conflictOwner` can just iterate `allCases` and
`register` no-ops on an unbound item. A registered window-command shortcut still runs nothing while the
feature switch is off — `WindowCommandCoordinator.runWindowCommand` re-checks it (see
[window-management.md](window-management.md)); a system-action shortcut likewise goes through
`SystemActionCoordinator.runSystemAction(id:)`, so the confirmation gate holds for a hotkey exactly as it does for the
palette.

## Modifier-only shortcuts

Every recorder accepts a single or double press of a lone modifier, including Globe/fn. Command,
Control, Option and Shift remember the Left or Right identity reported by macOS after remapping.
Single bindings display a small L/R inside the recorder's glyph cap; double bindings display only
the two modifier glyphs while retaining their side for matching and conflicts. Ordinary key
combinations remain side-agnostic. `ModifierKeyDetector` uses injected timestamps and device
flags, so holding both sides or unwinding a chord cannot create a new lone press. Holding a modifier
while recording saves its single binding when released. Existing generic double-tap bindings keep
their meaning; conflicts with overlapping sided double taps are refused rather than overwritten.

The recorder waits briefly after the
first release so another press can select the double binding; otherwise it saves the single one.
Globally, a single modifier fires on release when no double-tap action is bound. When both are bound,
the single action waits until the double-tap window expires. Another modifier, key, or mouse click
cancels the gesture, even while a single tap awaits the second. Both the monitor and the recorder
track Globe from the physical `kVK_Function` keycode, not just the fn flag, because F-keys also carry it.
It shares the double-tap's listen-only monitor, permission warning, lifecycle and pause while
recording. macOS may perform its own Globe action too; set “Press fn/Globe key to” to “Do Nothing” in
Keyboard settings if it conflicts. Globe+key chords use Carbon registration, like other combos.

Dictation's hold-to-talk mode reserves its single physical modifier across both tap gestures. It
starts after 250 ms held alone, so ordinary modifier+key chords do not briefly start recording. Another
key, modifier or mouse click cancels a pending or active hold; Return and Escape belong to the dictation
panel while listening. Release finishes the recording. Pausing, rebinding, disabling Dictation,
session changes and tap teardown cancel any hold. Double-tap bindings require toggle mode.

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

`ModifierTapMonitor` is the one platform file. It is a **listen-only** `CGEventTap` and it installs only
while a modifier-only shortcut is bound, so users who never use the feature pay nothing. Two
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

`HyperKeyManager` turns one physical key — Caps Lock or any of the eight side-specific modifiers —
into the ⌃⌥(⇧)⌘ chord system-wide. It owns the lifecycle and the policy; `HyperKeyTap` is the engine, a
**modifying** `CGEventTap`, a separate layer from `HotKeyCenter` because Carbon cannot intercept a lone
key at all. The rewritten flags flow onward into Carbon matching, so existing combo hotkeys fire from
Hyper+key with no extra registration.

Which key is chosen persists as a `HyperKeyPhysicalKey` raw value under `hyperKeyPhysicalKey` —
renaming a case is a migration, and a removed case decodes to `.none`. **F-keys are deliberately not
candidates:** the top-row media functions fire *below* the tap, and catching them earlier takes a
raw HID listener, which needs Input Monitoring — a permission Tinycast never asks for.

`HyperKeyManager.apply()` is the one funnel. Settings, sleep, lock, session switches and blocking apps
all call it, and it converges on what the settings ask for: no key is `.off`, a running blocker is
`.blocked`, a pause reason is `.paused`, a refused remap is `.remapUnavailable`; otherwise the remap goes
in, the tap installs, and the status is `.active` or `.needsAccessibility`.

### Caps Lock has to stop being Caps Lock

The caps-lock toggle — both the LED and the latch — happens below every `CGEventTap`, so no tap can
suppress it. The key must therefore stop being Caps Lock **at the source**: while Caps Lock serves as
Hyper, `KeyboardRemapper` puts a `UserKeyMapping` entry remapping it to **F18** on every keyboard
(see below). The tap then intercepts F18 in its place. The remap never survives a reboot.

A Caps Lock that still arrives raw means some keyboard has lost the remap. The tap passes it through
as Caps Lock and `HyperKeyManager` re-merges every keyboard; when one needed it, the latch that press
set is undone. Nothing else changes the latch while the key is remapped, so a raw press with every
keyboard already mapped leaves it alone.

Once remapped, Caps Lock arrives as **keyDown/keyUp** rather than `flagsChanged`. Both ends are
converted into Left Control `flagsChanged` transitions, so everything downstream sees the Hyper chord
move with the key rather than a swallowed press. That conversion is also why the **fn bit is scrubbed
from both ends**: every function key reports `NX_SECONDARYFNMASK`, harmless on a keyDown but read as a
real fn press once the event is a `flagsChanged`, which fired anything bound to fn on every Hyper
press. Only the Hyper key's own two events are scrubbed, so Hyper+F-key and Hyper+arrow keep the fn
bit they are entitled to. A classic `IOHIDSystem` connection reads and drives the Caps Lock LED and
lock state; it is used only by the explicit Quick Press toggle and the unlatch when the remap is
installed or repaired.

### Per-keyboard remapping

`KeyboardRemapper` writes through `HIDEventSystem`, the private IOKit SPI `hidutil` itself drives. It is
bound with `dlsym` in `Platform/HIDEventSystem.swift`, the only file that touches it, so a macOS that
drops a symbol reports `.remapUnavailable` instead of crashing. Each keyboard's original Caps Lock
mapping is preserved. A matching entry already placed by another tool is left unowned; Tinycast only
restores an original while the keyboard still carries its own installed mapping. Entries for other
keys and later replacements by other tools survive teardown. A keyboard that rejects the write is
skipped and stays plain Caps Lock; only every connected keyboard rejecting it reports
`.remapUnavailable`. With no keyboard connected, as after wake before a Bluetooth keyboard
reconnects, the remap succeeds and hot plug places it.

Recovery records are saved before each write, keyed by the HID service's registry ID and the current
boot session. A route change records both its old and new mappings until the write completes. A crash
on either side of the write therefore restores the original, even with Hyper Key set to None on the
next launch. Failed cleanup retains its record and is retried on relaunch or keyboard reconnection.
Records from another boot are ignored because HID mappings do not survive a reboot. The client stays
alive after first use so connected keyboards receive the remap or finish pending cleanup.

The mapping comes off on unbind, on quit, while the Mac sleeps, while the screen is locked — a password
typed at the lock screen needs a real Caps Lock — and while another user's session is active, and goes
back on once none of those holds.

### Press tracking reads the event

A modifier's `flagsChanged` carries its own device bit (`NX_DEVICE…KEYMASK`) while that key is down,
so `ModifierKey.held(in:)` reads each press and release of a modifier Hyper key from the event itself.
A hold dropped mid-press — by a Secure Input transition, a tap timeout or a pause — costs at most the
rest of that press and can never invert the key. Toggling instead would let one dropped hold read
every later release as a press, leaving the chord on every keystroke; querying `CGEventSource` key
state **races the release**. Nothing toggles: Caps Lock is a press only once remapped, never as its
raw latch. Work that posts events or touches IOKit is deferred to the next runloop turn rather than
run inside the tap callback, where it would risk re-entrancy.

The flags OR'd into every rewritten event are the generic ⌃⌥(⇧)⌘ masks **plus the left-side device
bits** (`NX_DEVICE…KEYMASK`, from `IOLLEvent.h`). Some consumers distinguish sides, and generic-only
flags do not always read as fully pressed. The Hyper key's own residue is scrubbed in the same pass:
Caps Lock's alpha-shift bit, or — for a key modifier outside the Hyper set — its generic mask and both
device bits. Events the tap posts carry a `"TYCT"` marker in `.eventSourceUserData`, the same FourCC
`HotKeyCenter` uses, so the tap never reacts to its own synthetics.

A Quick Press key is posted with **`flags` cleared explicitly**, like every other synthetic in the app.
A keyboard event built from `.combinedSessionState` inherits the source's modifiers, and the release
that ended the hold is still in flight a runloop turn later — so the Escape went out as ⌃⌥⇧⌘Escape.
Terminals read the raw `0x1B` and did not care; a focused field editor and any exact-match keymap
swallowed it, which is why Quick Press worked in Ghostty but never in Zed or the palette itself.

### Conflicts and diagnostics

`HyperKeyConflictPolicy` is the pure rule, tested by `hyper-key-test`; `HyperKeyConflictScanner` reads the
machine for it.

- **Known apps.** Hyperkey and Superkey bring a Hyper Key of their own and are **blocking**: while one
  runs ours stays `.blocked`, says so once in a HUD, and comes back by itself when it quits — KVO on
  `NSWorkspace.runningApplications` re-runs `apply()`, but only for those bundle IDs. Launch and
  terminate notifications cannot do it: macOS skips them for menu-bar apps, and both blockers are ones. BetterTouchTool is a
  **warning**, listed and never acted on. Other running event taps are not conflicts: most are benign.
- **Karabiner.** It seizes the real keyboards and types through its virtual keyboard, so that one gets
  the remap too. A conflict is that keyboard already sending our key elsewhere, or the selected profile
  in `~/.config/karabiner/karabiner.json` remapping the key.
- **Modifier Keys.** System Settings stores `com.apple.keyboard.modifiermapping.<vendor>-<product>-0`
  per keyboard in the by-host global domain, `0-0-0` being the default. One that moves Caps Lock defeats
  a HID remap, so it is reported with a link to Keyboard settings.

The Settings **Status** row carries a coloured dot, and **Diagnostics…** opens a snapshot from
`HyperKeyManager.diagnostics()`: Active, Active Key, Event Tap, Run Loop Source, Secure Input, Remapped
Keyboards, Conflicting Apps, Karabiner and Caps Lock mapping conflicts, with **Refresh** and **Restart
Hyper Key**.

### Secure Input

While an app holds Secure Input, macOS hides every keystroke from every event tap, so no tap can build
the chord. `SecureInputMonitor` polls `IsSecureEventInputEnabled` on the health tick, and a transition
drops any half-held chord, since the tap saw neither end of what was typed inside. Diagnostics name the
holder from the `kCGSSessionSecureInputPID` macOS records on the console session in `IOResources` —
hedged, because it is often wrong — and lead with running password managers and terminals.

Carbon hotkeys still fire inside Secure Input, and both remedies are built on that:

- **Off (the default):** with Caps Lock as Hyper, an F18 hotkey is registered for the duration, so a
  press explains in a HUD why nothing happened.
- **Secure Input Compatibility** (Caps Lock only): Caps Lock is remapped to **Right Control** instead of
  F18, because Secure Input still delivers modifiers. Outside it, the tap treats Right Control as the
  Hyper key, which is why physical Right Control shortcuts are reserved while it is on. Inside it,
  `HotKeyManager.setSecureInputEquivalents` registers every Hyper combo again as ⌃ plus its key
  (`KeyShortcut.secureInputEquivalent(of:)`), rebuilt with the bindings and dropped when Secure Input
  ends. The Carbon event's device flags select Right Control without querying mutable keyboard state.
  Left Control never triggers Hyper. An existing Tinycast Control binding shares the registration and
  still runs from Left Control; Dictation receives the release for whichever action began the press.
  Rebuilding or pausing registrations cancels an outstanding hold. Carbon reserves these Control
  combinations during Secure Input even when Left Control has no Tinycast binding.

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

Like every keyboard tap it needs the **Accessibility** grant; choosing a key in Settings is the one
place that prompts for it. A one-second watchdog runs while a key is live: it retries installation
until the grant lands, notices revocation, revives a tap the system disabled on timeout or user input,
and polls Secure Input. The HID remap outlives the process, so `applicationWillTerminate` takes it off
every keyboard before exiting.

## The Dictation key

Apple's 🎤 key (Consumer `0xC000000CF`) can't be recorded. While a recorder is open or a binding uses
F20, `DictationKeyManager` remaps it to **F20**, a bare F-key Carbon fires on press and release, even
in Secure Input, with no tap or permission. Otherwise, and in other users' sessions, macOS Dictation
keeps it. F20 keycaps draw as `mic`.

## Recorder

The settings recorder (`Features/HotKeys/UI/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyManager.recordingAction` state, and keys are captured by local
NSEvent monitors while both engines are paused. It records combos and single or double modifier taps,
including their reported side, by feeding its `.flagsChanged` / `.keyDown` monitors into the same pure detectors
as the global monitor, so recording needs no event tap and no permission.

Setting `recordingAction` is what starts and stops the capture, so there is exactly **one**
`ShortcutCaptureSession` (`HotKeys/Service/`) for the app rather than one per row — which is what lets the
callout above the field render the live state from outside the row that opened it. The field itself
only ever shows the binding; the prompt, the live preview and the conflict message all live in the
callout. See [ui.md](../ui.md#the-shortcut-recorder-callout).
