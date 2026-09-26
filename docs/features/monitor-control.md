# External monitor controls

Hardware brightness, volume and mute over DDC/CI on Apple Silicon. The feature is automatic
when a supported monitor and Accessibility permission are available. Settings → Monitor Control,
under Features beside Window Management, contains an enable switch, a default-on fine-grained
adjustments switch, detected monitor names,
and a short pointer-placement hint for brightness, shown only while enabled. Missing keyboard permission points to Settings
→ Permissions; technical capability details and manual reprobe are not exposed in this pane.
The switch uses an explicit blue on-state so an enabled feature does not look off when the Settings
window loses focus; its accessibility representation remains a native toggle. System Actions remains
dedicated to launcher commands.

## Invariants

- Brightness targets the physical display under the pointer at key-down. Repeats and release
  retain that target. Built-in and mirrored screens are excluded; screens without a uniquely
  matched physical DDC service never intercept keys.
- Volume and mute target the monitor uniquely matched to the default HDMI/DisplayPort audio
  output, regardless of pointer location. Name normalization preserves model numbers. Headphones,
  USB audio, aggregate outputs and ambiguous names keep native macOS behavior. Tinycast never
  changes the audio output. An output change during a held key stops further monitor writes until
  a fresh press; the consumed gesture is not handed to the new output mid-press.
- Each VCP control is probed independently. A valid current value and range are required;
  monitor levels are never guessed or restored from preferences on startup or wake.
- Only media brightness/volume/mute and the dedicated 144/145 brightness events are handled.
  Ordinary function keys and Option/System Settings shortcuts pass through. Fine-grained adjustments
  default on for brightness and volume: 64 steps across the hardware range rather than the standard
  16, rounded to a hardware unit. Option–Shift temporarily reverses the preference: larger steps when
  fine adjustments are on, smaller steps when off. Mute is unchanged. Preference changes update the
  routing snapshot immediately without reprobe or hardware writes of their own.
- The event tap reads a mutex-protected snapshot and publishes commands. It does no I²C work.
  All I²C operations run in one cancellable detached worker, serially, with coalesced writes.
- Each burst refreshes the actual hardware value once, then applies coalesced adjustments to its
  last written target. A temporarily unavailable initial read uses the previously verified value;
  it never initializes a monitor from a guessed value. Coalescing preserves clamping and direction
  reversals. Nonzero volume adjustments clear supported hardware mute, as native volume keys do.
- Writes are serialized with an 80 ms pause; unchanged targets are skipped and failed writes receive
  three bounded attempts. Readback starts after 350 ms without input for that control, with retries
  separated by 80/160/320 ms. A new repeat supersedes an in-flight read without marking the control
  unavailable. Valid but different readings reconcile the final level; exhausted write/read failures
  disable that control until reprobe and log the failed stage to the MonitorControl hardware log.
  Generation checks invalidate operations during reconnects, disable and shutdown.
- Key presses update and pin the HUD immediately, independently of hardware completion. It shows
  the requested level while pending, then the hardware reading once settled. Only the current
  interaction can start its dismissal timer; stale results cannot hide or replace newer feedback.
- A failed control stops intercepting new presses until reprobed. Consumed events are never
  replayed. Reconfiguration invalidates queued work and results by generation.
- The default-on `externalMonitorControlsEnabled` preference is excluded from backups:
  importing settings cannot enable interception. `externalMonitorFineAdjustments` is backed up:
  changing the step size grants no capability.

## Ownership and transport

`AppCore` owns `MonitorControlCoordinator`. It owns the event listener, hardware session and HUD,
uses `HealthTicker` for permission/tap recovery, and observes screen, sleep/wake and audio changes.
`stop()` removes observers, tears down the tap and cancels the worker and result consumers.

The transport dynamically resolves private IOKit IOAVService functions and CoreDisplay metadata.
Missing symbols and unsupported architectures leave system keys alone. Discovery follows
MonitorControl's IORegistry framebuffer/service traversal; location, EDID product/vendor and serial
matching must identify a unique service in both directions.

DDC timing and checksums follow the pinned MonitorControl sources listed in `NOTICE.md`.
Reads validate response type, control, status, checksum and level range. The LG HDR DQHD used
for development returns a zero length byte with the checksum for the standard `0x88` header;
the parser restores that byte before validating the checksum. Recorded replies guard this quirk.
There are no software-dimming, Intel, or external-tool dependencies.

The HUD is rendered by Tinycast through `HUDPresenter` on the explicit target screen.
It reconciles requested levels with hardware readback, including mute, and does not invoke the private native macOS OSD.
Existing launcher system actions retain their CoreAudio behavior.

## Verification

`./Scripts/run-tests.sh monitor-control-test` covers packets, matching, routing, levels,
modifiers, default fine steps, step-size preference changes, held keys, coalescing and generation
changes without touching hardware.
`./Scripts/run-tests.sh monitor-session-test` drives the real asynchronous worker through a fake
transport, including continuous up/down repeats, monitors refusing reads while busy, transient read/write
failures, delayed replies, superseded verification, redundant endpoint writes, hardware rounding,
blocked I/O, failures, reprobes and disconnection during an operation or settling.
`./Scripts/run-tests.sh monitor-hud-test` exercises the real presenter's pending/dismissal timers
with an offscreen panel stub; it never displays test windows on the user's desktop.
`./Scripts/run-tests.sh monitor-settings-test` renders the switch in light/dark and active/inactive
appearances, checking that on stays blue and off stays neutral without changing app preferences.

For read-only diagnosis with a connected monitor:

```sh
swiftc -swift-version 6 Tinycast/Features/MonitorControl/Model/*.swift \
  Tinycast/Features/MonitorControl/Service/MonitorDDCTransport.swift \
  Tinycast/Features/MonitorControl/Service/MonitorHardwareTransport.swift \
  Tinycast/Features/MonitorControl/Service/MonitorAudioOutput.swift \
  Tests/monitor-hardware-probe.swift -o /tmp/tinycast-monitor-probe
/tmp/tinycast-monitor-probe
```

The probe prints service matching, supported VCP values and audio matching. By default it sends
Get VCP queries only and does not install a keyboard tap. The explicit `--verify-writes` option
temporarily changes brightness/volume by one hardware unit and toggles mute, reads each change
back, then restores and verifies each original value. Pause other monitor controllers first.

Manual acceptance requires a Debug build and Accessibility permission. Disable other monitor-key
handlers (including MonitorControl) during this check: brightness on the external screen, volume
and mute with the monitor selected as sound output regardless of pointer location, native brightness
over the built-in screen and native audio with headphones, normal/fine/held keys, HUD
placement, unplug/replug, sleep/wake, permission revocation/regrant and the feature switch. Confirm
monitor values in its own menu and verify the Mac's brightness/volume do not also change.

### Development verification, 2026-09-26

The M3 MacBook Air / LG HDR DQHD DisplayPort connection passed discovery, audio-output matching,
and write/readback/restore checks: brightness `100 → 99 → 100`, volume `24 → 23 → 24`, and
mute `2 → 1 → 2` (`2` is unmuted). The monitor's original settings were restored and verified.
With Xcode 27.0 (27A266a) installed and first-launch setup completed, all 83 harnesses pass,
including monitor routing, worker, HUD and settings harnesses and the settings-backup exclusion. SwiftLint and settings-search
pass with existing lint warnings outside this feature; model-purity and whitespace checks pass.
The Xcode project was regenerated.

The complete arm64 Debug app and embedded `ClipboardTextHelper` build successfully with
`CODE_SIGNING_ALLOWED=NO`, using `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
There are no Swift compiler warnings; Xcode reports only skipped App Intents metadata extraction
because the app has no `AppIntents.framework` dependency. The build is at
`build/DerivedData/Build/Products/Debug/Tinycast Dev.app`.
It was subsequently rebuilt with ad-hoc signing and installed at `/Applications/Tinycast Dev.app`.

Live keyboard/HUD acceptance, headphones, held-key pointer movement, reconnects, sleep/wake and
permission-loss checks remain manual validation work; build and harness success do not verify them.
