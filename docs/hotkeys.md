# Hotkeys (in-house, zero dependencies)

`Core/HotKey/` holds:

- `KeyShortcut` — Sendable model, Carbon keycode + modifiers, layout-aware glyphs via `UCKeyTranslate`.
- `HotKeyCenter` — the Carbon `RegisterEventHotKey` layer, pausable.

`HotKeyManager` owns both: persistence, conflict lookup, and dispatch.

## Persistence

Shortcuts persist as JSON strings under `KeyboardShortcuts_<name>` UserDefaults keys — a **legacy
format** from the removed KeyboardShortcuts package, kept so old bindings survive. Bound app bundle
IDs, settings-pane bundle IDs, and stable command IDs live in separate arrays and are re-registered
on launch. Unknown command IDs are ignored so removing or downgrading a build stays safe.

## Recorder

The settings recorder (`Features/Settings/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyManager.recordingAction` state, and keys are captured by local
NSEvent monitors while all Carbon registrations are paused.
