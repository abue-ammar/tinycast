# 02 — Actor boundaries and typed notifications

Status: proposed. [Audit index](README.md). Read [hotkey invariants](../features/hotkeys.md) and
[palette invariants](../features/palette.md) before implementation.

## Findings

| ID | Confirmed pattern | Priority | Difficulty | Risk |
| --- | --- | --- | --- | --- |
| A01 | Workspace block observers use `.main` plus `MainActor.assumeIsolated`, despite native typed workspace messages being available on macOS 26 | P1 | Medium | Medium |
| A02 | Event taps, local event monitors and animation completions reach actor state through runtime assumptions | P1 after callback prototypes | Medium | High |
| A03 | [AppCore appearance KVO](../../Tinycast/App/AppCore.swift#L743) assumes actor isolation and updates the icon cache synchronously | P2 | Medium | Medium |

There are 35 `assumeIsolated` calls in 17 files. An assertion can be correct with documented main-run-
loop delivery; its presence is not evidence of a crash. The improvement is a compiler-visible
boundary where possible, while preserving the timing each callback requires. The project forbids
new `MainActor.assumeIsolated` calls.

## A01 — Workspace observations

Start with these call sites:

- [RunningAppsMonitor](../../Tinycast/Features/Launcher/Service/RunningAppsMonitor.swift#L17).
- [ClipboardManager](../../Tinycast/Features/Clipboard/Service/ClipboardManager.swift#L59), including
  session-resign/resume behavior.
- [HyperKeyTap](../../Tinycast/Features/HotKeys/Service/HyperKeyTap.swift#L150),
  [ModifierTapMonitor](../../Tinycast/Features/HotKeys/Service/ModifierTapMonitor.swift#L227), and
  [SnippetKeywordListener](../../Tinycast/Features/Snippets/Service/SnippetKeywordListener.swift#L220).
- [WindowMover termination observation](../../Tinycast/Features/WindowManagement/Service/WindowMover.swift#L115).

Use `NSWorkspace`'s native typed message observers on its own notification center, and store their
native observation tokens with the existing owner. Consume the typed application payload instead of
casting `userInfo`. Prefer synchronous main-actor message delivery when a session transition must
clear state immediately. An async sequence is suitable only where deferred delivery is acceptable.
The [Swift 6.2 announcement](https://www.swift.org/blog/swift-6.2-released/) describes this typed
notification model; the installed SDK and a target-26 probe confirm workspace support.

Do not convert every notification by name. [IconStyleMonitor](../../Tinycast/Platform/Images/IconStyleMonitor.swift#L15)
uses an undeclared icon-style signal, and Notes observes text storage and view geometry. Verify each
native message's availability and semantics. Keep the existing RAII
[NotificationToken](../../Tinycast/Platform/NotificationToken.swift) for remaining block observations.
Avoid inventing a parallel typed-notification framework for one unsupported signal.

## A02 — Synchronous platform callbacks

The critical event-tap paths are
[HyperKeyTap](../../Tinycast/Features/HotKeys/Service/HyperKeyTap.swift#L9),
[ModifierTapMonitor](../../Tinycast/Features/HotKeys/Service/ModifierTapMonitor.swift#L7),
[SnippetKeywordListener](../../Tinycast/Features/Snippets/Service/SnippetKeywordListener.swift#L7), and
[CommandEscapeTap](../../Tinycast/Palette/CommandEscapeTap.swift#L5).
They must synchronously decide whether to pass, suppress or rewrite an event. Returning before the
decision or sending borrowed C pointers into a `Task` would break the feature.

1. Prototype an explicitly main-actor callback at the actual SDK boundary, following the already
   migrated [HotKeyCenter callback](../../Tinycast/Features/HotKeys/Service/HotKeyCenter.swift#L110).
   Verify that the callback signature compiles in Swift 6 mode and that installation/delivery really
   is confined to the main run loop. A type annotation alone is not proof of C runtime scheduling.
2. Keep pointer decoding and event mutation within the callback's lifetime. Exchange only plain
   values with policy code. Do not hop asynchronously for a synchronous return value.
3. Apply the same approach to
   [ShortcutCaptureSession](../../Tinycast/Features/HotKeys/Service/ShortcutCaptureSession.swift#L39),
   [PalettePanel](../../Tinycast/Palette/PalettePanel.swift#L81) and the relevant local monitors.
   ShortcutCaptureSession already contains an explicitly annotated mouse handler as a local precedent.
4. For [PanelTransition](../../Tinycast/DesignSystem/Interaction/PanelTransition.swift#L17) and
   [MenuPanel](../../Tinycast/Palette/MenuPanel.swift#L345), use a typed completion when the SDK supports
   it. Otherwise defer only the actor work whose extra turn is acceptable, with existing visibility
   and lifetime checks. Preserve fade interruption, shadow invalidation and exactly-once completion.
5. Treat an SDK signature that cannot represent required isolation as a concrete blocker to that
   item's replacement. Do not erase the issue with `unsafeBitCast`, extra suppressions or a new actor.

## A03 — Appearance and remaining callbacks

The appearance observer prevents a row from caching an icon under an outgoing appearance. A blind
`Task { @MainActor ... }` substitution can let the next render run before invalidation.
Prototype a compiler-visible synchronous callback and retain this cache-ordering invariant. If only
deferred delivery is available, establish an explicit appearance generation/cache key before using it.
Do not add a second observer or broad cache solely to remove an annotation.

For [NotesWindowController](../../Tinycast/Features/Notes/UI/NotesWindowController.swift#L130),
[SnippetsStore](../../Tinycast/Features/Snippets/Model/SnippetsStore.swift#L278) and timers, perform the
replacement with L02/M01. Preserve Notes' coalesced sizing and Snippets' watcher-generation checks.
Neither protected scrolling file may be edited.

## Validation and completion

Run `hotkey-test`, `palette-shortcut-test`, `palette-escape-test`, `keyboard-focus-test`,
`snippets-test`, `notes-editor-test`, `appearance-test` and `icon-cache-test` as applicable, then the
full suite and build. Existing policy tests do not establish real event-tap delivery.

Manual checks must cover left/right modifiers, Globe, Hyper press/hold, recorder cancellation,
synthetic-key suppression, tap recovery, fast user switching, sleep/wake, animation interruption and
system/light/dark appearance changes. Arrange an explicit idle window before pointer/keyboard tests.

Done when each migrated callback has explicit isolation and correct token lifetime, required
synchronous decisions remain synchronous, and no new runtime assumptions or data-race suppressions
have been added. Roll back one callback family at a time if timing or keyboard delivery regresses.
