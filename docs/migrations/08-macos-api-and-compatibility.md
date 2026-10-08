# 08 — macOS APIs, legacy formats and platform exceptions

Status: proposed. [Audit index](README.md). Keep the macOS 26 floor; remove a behavior only after the
plan has established that the change is intended.

## Findings and ratings

| ID | Finding and classification | Priority | Difficulty | Risk |
| --- | --- | --- | --- | --- |
| O01 | 23 legacy app-activation calls in 16 files; confirmed superseded API | P1 | Low | Medium |
| O02 | String-based deprecated filenames pasteboard format; confirmed compatibility behavior | P2, behavior decision | Low | High |
| O03 | AI model selection accepts the old `chatGPT` serialized case; confirmed compatibility decoder | P3, behavior decision | Low | Medium |
| O04 | Dynamic private/undeclared platform symbols; confirmed dependency, replacement parity unproven | P2, investigation | Medium | High |
| O05 | Clipboard capture does not consult the modern pasteboard access-behavior API; coverage review | P2, investigation | Medium | High |
| O06 | Six `NSLog` calls in five files; confirmed mismatch with Logger convention | P3 | Low | Low |
| O07 | Fifteen file-picker `runModal()` calls use nested modal loops | P1 | Medium | Medium |
| O08 | Extensions uses one `NSAlert.runModal()` despite the project prohibition | P1 | Low–Medium | Medium |

O02 and O03 implement observable behavior covered by existing tests. Their removal is not automatically
authorized by preferring modern APIs, and latest macOS does not guarantee that other applications only
emit modern data formats.

## O01 — Modern activation

Examples are [AppWindowController](../../Tinycast/Windows/AppWindowController.swift#L144),
[FolderPicker](../../Tinycast/Platform/FolderPicker.swift#L16),
[NotesWindowController](../../Tinycast/Features/Notes/UI/NotesWindowController.swift#L40),
CalendarCoordinator, BackupActions, QuickActionCoordinator, ExtensionCoordinator and AIChatCoordinator.
Find every occurrence with:

```sh
rg -n 'NSApp\.activate\(ignoringOtherApps:' Tinycast --glob '*.swift'
```

Replace the call directly with `NSApp.activate()`. Apple directs developers to the modern cooperative
activation APIs in [What's new in AppKit](https://developer.apple.com/videos/play/wwdc2023/10054/).
The current SDK marks the old method for future deprecation, which explains why this build emits no
deprecation warning for it. Existing
[modern activation](../../Tinycast/Features/AI/UI/AIChatCoordinator.swift#L156) is a local precedent.

Keep focus restoration and accessory-window behavior. Activation is a request, not a guarantee; use
cooperative yielding only where the app owns a real handoff. Do not invent a compatibility wrapper,
activate nonactivating camera/palette surfaces, or replace existing next-turn focus handling blindly.

## O07/O08 — Async pickers and Tinycast dialogs

[FolderPicker](../../Tinycast/Platform/FolderPicker.swift#L17) and
[ExecutablePicker](../../Tinycast/Platform/ExecutablePicker.swift#L19) are synchronous entry points;
other picker loops occur in Backup, Custom Commands, File Search, Launcher settings, AI Chat, window
layout arguments, and extension forms/settings.

Migrate file pickers to the native async `NSOpenPanel`/`NSSavePanel` presentation API and await the
result from their existing coordinator/action lifetime. `await NSOpenPanel().begin()` typechecked
without warnings for target macOS 26.0 with Swift 6.4. Preserve panel configuration, multi-selection,
hidden files, package/alias behavior, cancellation and focus restoration. Use a sheet only when an
appropriate parent window is already part of that flow. Keep native filesystem pickers; they are not
Tinycast's confirmation dialogs. Update synchronous callers together, and guard against repeated
actions stacking presentations.

[ExtensionManager.openWithPicker](../../Tinycast/Features/Extensions/Service/ExtensionManager.swift#L967)
builds an NSAlert with up to four application choices and Cancel. This directly violates AGENTS.md.
Route it through the existing extension coordinator to AppCore's single-owned
[DialogController.choose](../../Tinycast/Windows/Dialog/DialogController.swift#L32), which already
supports multiple actions. Preserve candidate ordering, cancel behavior and the single-candidate
shortcut. Do not add another presenter or extension-specific view to DesignSystem.
Update architecture.md's currently inaccurate statement that NSAlert is never used when this fix lands.

## O02/O03 — Compatibility behavior with data consequences

[PasteboardFiles](../../Tinycast/Platform/PasteboardFiles.swift#L6) constructs the string
`NSFilenamesPboardType`, so the compiler cannot warn about the deprecated global. Apple documents the
[old format](https://developer.apple.com/documentation/appkit/nsfilenamespboardtype) and modern URL
writing. Existing modern file-URL handling is already bounded and avoids uncapped Finder selections.

Determine whether supported current applications still supply legacy-only boards. If dropping them is
the intended product behavior, delete the fallback and update `pasteboard-test`, `clipboard-test`,
`clipboard-file-performance` and clipboard docs together. Preserve matching/limit behavior and modern
representation precedence. If compatibility remains required, keep it as an explicit inter-app format
decision, not a claim that it supports an older OS. Do not replace the bounded reader with an unbounded
`readObjects` call merely to use a newer spelling.

[AIConnection's model-selection decoder](../../Tinycast/Features/AI/Model/AIConnection.swift#L220) accepts
`chatGPT` as `codex`. [ai-provider-test](../../Tests/ai-provider-test.swift#L1071) intentionally covers it.
Inspect persisted selections and backup behavior before removing the alias. Delete decoder/test/doc
support together only if losing that old spelling is intended. Do not confuse this coding key with
the current ChatGPT subscription service, which remains active functionality.

## O04/O05 — Investigate actual platform parity

Dynamic dependencies include:

- [AXWindowAccess](../../Tinycast/Features/WindowManagement/Service/AXWindowAccess.swift#L112):
  `_AXUIElementGetWindow` for stable window identity.
- [DictionaryService](../../Tinycast/Features/Dictionary/Service/DictionaryService.swift#L42): undeclared
  Dictionary Services record calls for rich definitions, with public plain-text fallback.
- [SystemActionRunner](../../Tinycast/Features/SystemActions/Service/SystemActionRunner.swift#L332):
  private login screen-lock symbol and undeclared Bluetooth power functions.
- [IconStyleMonitor](../../Tinycast/Platform/Images/IconStyleMonitor.swift#L53): an undeclared workspace
  icon-style notification.

No public replacement with equivalent behavior was established in this audit. Research the current
SDK and prototype a replacement against the actual feature before proposing deletion. Runtime symbol
checks protect against missing private capabilities, not an older deployment target. A latest-only
policy cannot make a private API stable. Record any remaining capability exception in the feature doc,
keep it inside the existing platform/service boundary, and test symbol absence/failure. Never guess a
replacement, direct-link a private symbol to silence the fallback, or retain duplicate paths after a
public migration succeeds.

[ClipboardManager.poll](../../Tinycast/Features/Clipboard/Service/ClipboardManager.swift#L129) reads
pasteboard content after change-count detection, without `accessBehavior`. Review allow/ask/deny
handling against the installed SDK and Apple's
[NSPasteboard API](https://developer.apple.com/documentation/appkit/nspasteboard/).
The absence of an explicit check is not proof of unauthorized access or a reproduced privacy bug.
Verify current system behavior, failed reads and resume-after-access-change before changing capture.
Keep permission/capture policy in the existing owner, with no new global monitor or preference.

## O06 — Diagnostics

NSLog is not an SDK deprecation. Replace the six calls in HotKeyCenter, HyperKeyTap,
ModifierTapMonitor, SnippetKeywordListener and ShellCommandRunner with the existing `Logger` convention,
using appropriate subsystem/category and privacy for diagnostic arguments. Keep user-facing failures
on the existing HUD/dialog route. Avoid introducing another logging abstraction.

## Validation and completion

Run `palette-escape-test`, `hotkey-test`, `pasteboard-test`, `clipboard-test`, `ai-provider-test`,
`ext-test`, `window-command-test`, `dictionary-test`, `system-action-test`, affected backup/settings
harnesses and the full suite/build. Manually verify focus, picker Cancel/multiple selections, extension
Open With, launch from a background accessory app, pasteboard allow/deny and real platform capabilities.

Done when superseded activation/modal flows are migrated, the NSAlert violation is removed, and each
retained legacy/private path has an explicit current requirement. Keep behavior deletions separate
from mechanical API changes and roll back by flow if focus, imports or saved selections regress.
