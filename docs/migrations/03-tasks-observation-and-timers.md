# 03 — Task ownership, Observation and timers

Status: proposed. [Audit index](README.md). Depends on T01/T02 for compiler and target validation.

## Findings

| ID | Confirmed pattern | Priority | Difficulty | Risk |
| --- | --- | --- | --- | --- |
| L01 | Seven manually rearmed `withObservationTracking` calls in six files | P2 | Medium | Medium |
| L02 | Three Combine timer publishers, plus owner-level Timer callbacks with isolation assumptions | P2 | Medium | Medium |
| L03 | [Paster](../../Tinycast/Features/Clipboard/Service/Paster.swift#L22) schedules uncancellable paste events after fixed delays | P1 | Medium | High |
| L04 | Numerous detached jobs combine finite computation, I/O and resource cleanup under one spelling | P2 | Medium per feature | Medium |

Unstructured tasks are not automatically leaks. Short UI actions and stream producers can be valid,
and the AI stream providers already cancel their producing tasks in `onTermination`. Prioritize
tasks that own resources, can outlive a session, or publish stale results.

## L01 — Replace manual rearming selectively

Affected owners are [AppCore](../../Tinycast/App/AppCore.swift#L755),
[AppIndex](../../Tinycast/Features/Launcher/Service/AppIndex.swift#L570),
[HyperKeyTap](../../Tinycast/Features/HotKeys/Service/HyperKeyTap.swift#L168),
[SettingsFileRepository](../../Tinycast/Features/Settings/Service/SettingsFileRepository.swift#L93),
[NotesWindowController](../../Tinycast/Features/Notes/UI/NotesWindowController.swift#L253), and
[AIChatWindowChrome](../../Tinycast/Features/AI/UI/AIChatWindowChrome.swift#L164).

Prototype macOS 26's `Observations` for a small, value-returning settings projection first. It emits
transactional snapshots and avoids one-shot will-set rearming; see
[SE-0475](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md).

1. Read the initial snapshot explicitly where boot depends on it; do not accidentally apply it twice.
2. Observe a focused `Sendable` value, such as a tuple or existing setting type, rather than the whole
   owner. Avoid a new generic observation layer.
3. Store the consuming task on the existing owner and cancel it on stop or isolated teardown.
4. Avoid retaining the owner for an endless loop. Capturing weakly and immediately promoting `self`
   for the whole loop still creates a cycle when the owner stores the task. Read through a separately
   owned settings value and reacquire the owner only for each effect.
5. Preserve SettingsFileRepository's atomic snapshot/baseline semantics and its explicit quit flush.
   Migrate it after a simpler monitor establishes the pattern.

Coalescing is appropriate for state projections, not key presses, process messages or every intermediate
setting transition. Verify rapid on/off/on effects and route changes. Keep necessary ordering explicit.
The Swift 6.4 advanced tracking overload is macOS 27-only and is outside this baseline.

## L02 — Polling and delayed UI state

Replace the timer publisher in
[PermissionsSettingsView](../../Tinycast/Features/Settings/Panes/PermissionsSettingsView.swift#L10),
[QuickActionsSettingsView](../../Tinycast/Features/QuickActions/Settings/QuickActionsSettingsView.swift#L17),
and [OnboardingView](../../Tinycast/Features/Onboarding/OnboardingView.swift#L14) with a view-scoped
`.task` loop that refreshes immediately, sleeps with a clock, and exits when cancelled. Preserve the
one-second permission-refresh behavior. Retain permission reads in the existing platform owner;
do not create a new permission singleton.

For [HealthTicker](../../Tinycast/Platform/HealthTicker.swift#L15),
[ClipboardManager](../../Tinycast/Features/Clipboard/Service/ClipboardManager.swift#L71), and
[PaletteWindowController's pop-to-root timer](../../Tinycast/Palette/PaletteWindowController.swift#L180),
use a stored cancellable task if it preserves timing, or a compiler-visible isolated Timer boundary.
Preserve the shared watchdog's weak subscribers, no timer while idle, clipboard rebaselining on
session resume, and close/reopen cancellation. Keep timer tolerance/coalescing where it matters;
measure wakeups before replacing run-loop timers globally.

The distributed input-source notification in
[GeneralSettingsView](../../Tinycast/Features/Settings/Panes/GeneralSettingsView.swift#L213) is an
external event stream. A view-scoped notification sequence may simplify its ownership, but converting
it is lower priority than removing the three timer-only Combine imports.

## L03 — Delayed paste delivery

Paster contains six `DispatchQueue.main.asyncAfter` calls. Some activate the previous app and later
post a global Command-V; others post to a captured process ID. Overlapping requests or a target change
during the delay can invalidate the intended destination. That is an inferred risk, not a reproduced
wrong-app paste in this audit.

Extend the existing Clipboard coordinator/Paster/TextInjection ownership instead of introducing another
singleton scheduler. Make the delayed operation awaitable or explicitly owned by its initiating owner.
Preserve acceptance/promote semantics and the fixed delay until activation measurements justify a
change. Validate destination identity and the relevant request/pasteboard generation before delivery.
Specify whether repeated paste actions queue or replace each other based on current behavior; do not
silently drop accepted requests. Cancellation must exit rather than falling through a `try?` sleep.

Keep directed in-place paste independent of focus-stealing activation, and preserve the synthetic-event
tag and internal clipboard marker. Reuse existing destination/session validity checks where applicable.

## L04 — Finite background work and cleanup

Use an awaited `@concurrent` function for suitable finite computation or decoding with checked
`Sendable` inputs/results. This can remove detached-task wrapping while inheriting structured
cancellation and priority. Add cooperative cancellation checks to long CPU loops where needed;
`@concurrent` alone does not interrupt them. Migrate one measured worker at a time.

Do not move blocking process waits, large pipe writes or capture-session calls into the cooperative
executor. P01/P02/C01 must establish appropriate I/O and session boundaries first.

[InstalledCLIProvider](../../Tinycast/Features/AI/Service/InstalledCLIProvider.swift#L273) has detached
file work and detached cleanup. Where a lifecycle operation can await cleanup, Swift 6.4's async
`defer` can make resource teardown part of the operation. Synchronous termination hooks need explicit
bounded completion; an unawaited cleanup task is not guaranteed to run before process exit. Do not use
macOS 27 cancellation shielding at a 26 floor.

## Validation and completion

Run `update-check-test`, `settings-file-test`, `launcher-settings-file-test`, `paste-sequence-test`,
`dictation-field-test`, `installed-ai-test` and the affected feature harnesses, then the full suite/build.
Add focused cancellation/ordering coverage only where existing tests do not exercise changed behavior.

Check repeated open/close, permission changes, rapid settings edits, close/reopen timers, cancellation
during sleep, repeated paste, target changes and stream teardown. Measure idle wakeups and ensure
closed views/owners deallocate. Done when resource-owning jobs have a clear owner and completion path,
obsolete timer imports are removed, and state observation cannot publish into an ended session.
