# 05 — Subprocess lifetime, pipes and extension runtime

Status: proposed. [Audit index](README.md). Read [custom command](../features/custom-commands.md),
[MCP](../features/mcp.md), [AI](../features/ai.md) and [extension](../features/extensions.md) invariants.

## Findings

| ID | Confirmed pattern | Priority | Difficulty | Risk |
| --- | --- | --- | --- | --- |
| P01 | [ProcessExit.wait](../../Tinycast/Platform/ProcessExit.swift#L14) blocks on a semaphore; [InstalledAIProbe](../../Tinycast/Features/AI/Service/InstalledAIProbe.swift#L45) performs blocking pipe reads and exit waits inside detached tasks | P1 | Medium | High |
| P02 | [MCPStdioTransport.send](../../Tinycast/Features/MCP/Service/MCPStdioTransport.swift#L126) writes to a pipe on MainActor, and its exit path drains stderr there; CLI adapters use detached blocking writes | P1 | Medium | High |
| P03 | [ToolRunner](../../Tinycast/Features/Updates/Service/ToolRunner.swift#L28) has an unowned timeout task and no caller-cancellation handler | P1 | Medium | Medium |
| P04 | [ExtensionRuntime](../../Tinycast/Features/Extensions/Service/ExtensionRuntime.swift#L23) asserts queue confinement for JS state and exposes an unsafe mutable weak delegate | P2 | High | High |

The code patterns are confirmed. Executor starvation, large-write UI stalls, inherited-pipe hangs and
runtime delegate races are inferred risks; this audit did not reproduce them.

## P01 — Suspending exit observation and blocking work

`Task.detached` runs on Swift's cooperative executor. It is not a dedicated blocking thread.
InstalledAIProbe's comment claiming detached work is never on a pool thread is incorrect. Its `run`
and `request` routines read synchronously and call `exit.wait()`; `request` also lacks the cancellation
registration used by `run`.

Extend the existing ProcessExit boundary with an asynchronous exit wait driven by termination
notification. Keep completion state and waiter registration synchronized so exit-before-registration
and concurrent waits are correct. Define cancelled-waiter removal and exactly-once completion;
cancelling one observer must not accidentally cancel another process owner's wait. Preserve launch
failure behavior and do not reintroduce `waitUntilExit()`.

Make AI probe reads event-driven where practical. Otherwise retain a narrowly scoped existing
blocking-I/O queue and await it; do not just replace `Task.detached` with `@concurrent`. Connect
caller cancellation to child termination, close pipes, bound output and await reaping. Handle the
race where cancellation arrives between the preflight check and launch. Timeout and forced-kill
policy must be explicit for children that ignore a polite termination request.

[ClipboardTextWorker](../../Tinycast/Features/Clipboard/Service/ClipboardTextWorker.swift#L10),
[DictationWorker](../../Tinycast/Features/Dictation/Service/DictationWorker.swift#L8) and
[ShellCommandRunner](../../Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift#L68)
already keep blocking work on Dispatch queues. Preserve this protection while migrating waits.
PTY streaming is a real requirement for shell behavior and cannot be replaced by a pipe blindly.
Keep a synchronous wait only for a concrete synchronous boundary that still requires it, such as
the bounded termination-time HID cleanup, rather than hiding it behind an async spelling.

## P02 — Writes, drain ordering and old-process callbacks

Make MCP pipe writes serial and awaitable on its existing transport owner. Requests, notifications and
declines must preserve framing and order, report write errors, and not block the main actor when a
child stops reading. Update protocol call sites together; no fire-and-forget write whose failure can
only become a request timeout. Keep `F_SETNOSIGPIPE`, byte bounds, final stderr and shutdown errors.

MCP's `drainStderr` uses `readDataToEndOfFile()` on MainActor. Move that drain off-main or make it
event-driven. A descendant can keep an inherited descriptor open after the direct child exits;
define a bounded final-drain policy instead of awaiting EOF forever.

Queued readability and exit callbacks can arrive after cleanup or reconnection. Attach the existing
transport session/process identity to delivery and reject stale chunks before parsing or failing
requests. InstalledCLIProvider already serializes writes by awaiting the previous task, but the actual
write still blocks a cooperative worker. Preserve serialization while correcting the execution
boundary. Do not create a second transport abstraction covering every subprocess in the app.

## P03 — Timeout task ownership

ToolRunner's timeout task remains alive after an early successful exit, holds the Process and is not
cancelled when the caller cancels. Cancellation can also prevent or prematurely complete a `try?`
sleep without representing successful timeout expiration.

Own the timeout alongside the operation, cancel it on every finish path, and make caller cancellation
terminate and reap the child. Race timeout, cancellation, launch failure and natural exit through one
completion state. Continue draining output without losing split UTF-8 sequences, and define an output
cap where callers do not need unbounded logs. The existing OutputCollector is the state holder to
improve with S01; no generic process manager is needed.

Swift 6.4 async `defer` can make asynchronous teardown awaited before return. Cleanup itself must
remain effective after cancellation. The 27-only cancellation-shield API cannot be used at the current
floor. The [Swift release](https://www.swift.org/blog/swift-6.4-released/) also introduces Subprocess
1.0, but it is a separate package, not a Foundation replacement already in the SDK. Adding it would
change Tinycast's no-package architecture and is not the proposed migration.

## P04 — JavaScriptCore confinement

Preserve the serial JS queue: synchronous Node shims, evaluation and timer callbacks must see one
ordering, and JSContext/JSValue must not cross executor boundaries. A new actor or main-actor JS
engine would conflict with existing rules and can change blocking shim semantics.

1. Audit every JS state access and mark queue-only entry points clearly. Use queue preconditions in
   appropriate debug paths to establish confinement.
2. Replace `nonisolated(unsafe)` delegate mutation with a single-owner startup or queue-serialized
   installation path. Account for the circular owner/runtime construction without introducing a
   competing singleton. Verify that no setter can run after boot begins.
3. Retain the existing runtime generation, host task cancellation and idle-waiter completion. Extend
   validity checks to queued UI delivery where necessary; JS shutdown must not publish stale renders.
4. Make shutdown completion awaitable where the caller needs resources closed before reboot or
   uninstall. Preserve fire-and-forget notification only where the caller's contract allows it.

`@unchecked Sendable` for the whole queue-confined runtime may remain necessary under the current
no-new-actors design. The improvement is a verifiable confinement proof and a smaller mutable seam.

## Validation and completion

Run `installed-ai-test`, `codex-turn-test`, `mcp-stdio-test`, `dictation-worker-test`,
`clipboard-text-test`, `custom-command-test`, `ext-test`, `ext-fetch-test` and `updates-test`, then the
full suite/build. Add scenarios for cancellation before launch, oversized input, a child that stops
reading, concurrent stdout/stderr, immediate exit, launch failure, ignored termination, reconnect and
late old-process delivery. Measure main-actor stalls and thread growth under simultaneous sessions.

Done when async waits suspend, blocking I/O has an explicit safe executor, process completion and
reaping are owned, and no ended process/runtime can mutate a new session. Roll back by transport or
runner, keeping source and harness changes together.
