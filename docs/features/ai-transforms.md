# AI transforms

AI transforms let users highlight text anywhere and run it through a named prompt — **Settings →
AI Transforms** holds the library. A transform runs from its launcher row or its own global
shortcut, sends the selection to an OpenAI-compatible chat-completions endpoint, and replaces the
selection in place with the result.

The pane carries the feature switch — off out of the box — and its launcher-visibility companion,
both in `AppSettings` and in settings backups, plus one global provider config (base URL and model;
per-preset model overrides are allowed). Switching the feature off empties the launcher section and
makes `AITransformCoordinator.runTransform` — the single funnel for palette activation and global
shortcuts — refuse to run anything; Carbon registrations and their bindings stay put, so re-enabling
restores every shortcut without re-registering. "Show in launcher" only hides the section; shortcuts
keep working.

## Invariants

- **`Model/AITransform.swift` and `Service/AIClient.swift` stay free of AppKit and SwiftUI**
  (Foundation plus URLSession) so `ai-transform-test` can compile them standalone. That is why the
  delivery step lives in `AITextDelivery` and the funnel in `AITransformCoordinator`.
- **The API key never leaves this Mac's Keychain.** It is stored through `SecretStore` under the
  account `ai.api-key`, is read only inside a request's lifetime, and is never included in a backup.
- **No idle cost when disabled.** No timers, event taps, monitors or caches anywhere in the feature;
  the store loads one small array at init, and the URL session exists only inside a request.
- One transform runs at a time; two overlapping runs would race for the same selection.

## Ownership and persistence

`AITransformStore` is owned by `AppCore` and persists the transform array as JSON in bundle-scoped
`UserDefaults`. Each transform has a stable UUID. Its launcher entry id is `ai-transform:<uuid>`,
and its hotkey uses `hotkey.aiTransform.<uuid>` plus the `boundAITransformIDs` index.

Editing preserves the UUID and therefore its favorite, visibility, and hotkey references. Deleting
goes through `AITransformCoordinator`, which unregisters the hotkey and clears those references
before removing the transform. Native settings backups include the transforms, their bindings, and
the provider config; the Keychain key does not ride along.

First-run presets ("Fix Spelling & Grammar", "Polish Writing", "Make Concise", "Summarize") are
seeded exactly once — on the enable transition, when the store is empty. An import that replaces the
library is never overwritten by seeding, and toggling visibility cannot resurrect deleted presets.

## Launcher integration

`AppIndex` owns an AI-transform slice alongside the custom-command slice, supplied on the main actor
by `setAITransforms`. It publishes ahead of the alphabetized `CommandCatalog` built-ins, each its own
launcher section, so the visible row order matches the flat palette selection while edits invalidate
fuzzy results without rescanning disk.

Only the user-facing name enters fuzzy matching; the prompt text is deliberately not searchable.

## Execution contract

`runTransform(id:)` gates on the feature switch, hides the palette, reads the focused selection via
`AccessibilityText`, then builds an `AICompletionRequest`: the preset prompt wrapped as the system
message (`systemInstruction` appends a no-commentary wrapper so a chatty model cannot corrupt an
in-place replace) and the selection as the user message. `AIClient.complete` posts to
`baseURL + "/chat/completions"` with `stream: false` and decodes `choices[0].message.content`.

Delivery mirrors Snippets' proven mechanics in `AITextDelivery`: an Accessibility in-place write
first; if the selection isn't directly writable, a synthetic ⌘V over the selection rides the real
clipboard with the original snapshot restored afterwards. If focus was lost mid-run, the result is
parked on the clipboard instead of pasted blind. The pasteboard handshake is reported back through
`onPasteboardMutation` → `ClipboardManager.synchronizeAfterTinycastPasteboardMutation`, so restoring
the original clipboard never lands in clipboard history.

## Reporting

Failures surface as Tinycast dialogs with friendly mapped errors: missing key or model is
"not configured", 401/403 is unauthorized, 429 is rate-limited, other statuses carry the provider's
message. Success is silent except for the outcomes worth saying out loud — clipboard fallback tells
the user where the result went.

## Manual checks

The delivery path needs a real focused text field and a live provider, so verify by hand:

1. Enable the feature; the four presets appear in Settings and in the launcher's AI Transforms
   section. Disable and re-enable: presets do not duplicate, and deleting all presets then toggling
   visibility does not resurrect them.
2. Select text in TextEdit, run a transform from the palette: the selection is replaced in place and
   clipboard history records nothing extra.
3. Bind a global shortcut, focus another app, trigger it: same replacement without the palette.
4. Clear the API key, run a transform: a "not configured" dialog appears and the selection survives.
5. Export settings, import on a scratch defaults domain: transforms, bindings and provider config
   return; no secret appears anywhere in the exported JSON.
