# 04 — Synchronization and checked Sendable boundaries

Status: proposed. [Audit index](README.md). Preserve feature ownership; this plan introduces no actor.

## Findings

| ID | Confirmed pattern | Priority | Difficulty | Risk |
| --- | --- | --- | --- | --- |
| S01 | Seven `NSLock` instances protect state separately from its declaration; several holders assert `@unchecked Sendable` | P1 | Low for simple holders; Medium for repository locks | Low–Medium |
| S02 | Image/cache wrappers assert thread safety for AppKit reference objects | P2 | Medium | Medium |
| S03 | `@preconcurrency` imports suppress SDK-global diagnostics at AX/IOKit boundaries | P3, verify narrow necessity | Low | Medium |

These are review/migration surfaces, not demonstrated data races. The strongest immediate improvement
is to make each lock own the state it protects. Capture and JS-runtime state need the separate C/P plans.

## S01 — Use the existing Mutex pattern

The local precedents are
[ExtensionFetcher](../../Tinycast/Features/Extensions/Service/ExtensionFetcher.swift#L108),
[ExtensionWebSocketBridge](../../Tinycast/Features/Extensions/Service/ExtensionWebSocketBridge.swift#L11),
and [DictationModelDownloader](../../Tinycast/Features/Dictation/Service/DictationModelDownloader.swift#L138).
`Synchronization.Mutex` is available below the app's floor. It couples protected state to scoped access;
see [SE-0433](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0433-mutex.md).

Migrate the smallest independent holders first:

| Location | Protected state | Required behavior |
| --- | --- | --- |
| [CalcDateFormatters](../../Tinycast/Features/Calculator/Model/CalcDateFormatters.swift#L20) | Formatter dictionary | Keep formatter creation/use inside protection and retain the 64-entry bound |
| [ExtensionInstaller.ResumeGuard](../../Tinycast/Features/Extensions/Service/ExtensionInstaller.swift#L266) | Completion flag | Take completion exactly once; resume outside the critical section |
| [ShellCommandRunner.StopFlag](../../Tinycast/Features/CustomCommands/Service/ShellCommandRunner.swift#L223) | Stop state | Preserve stop visibility and escalation behavior |
| [InstalledAIProbe.ProcessHandle](../../Tinycast/Features/AI/Service/InstalledAIProbe.swift#L13) | Process and cancellation state | Preserve cancellation-before-registration semantics |
| [ToolRunner.OutputCollector](../../Tinycast/Features/Updates/Service/ToolRunner.swift#L60) | Output bytes | Preserve split UTF-8 handling and concurrent callback safety |
| [SnippetRepository](../../Tinycast/Features/Snippets/Model/SnippetRepository.swift#L3) | Canonical directory lock table and mutation serialization | Preserve per-directory transaction ordering and conflict detection |

Keep a `let Mutex<State>` on the existing final holder, move associated mutable state into it, and
attempt ordinary checked `Sendable` conformance. For CalcDateFormatters this should remove both the
separate `NSLock` and `nonisolated(unsafe)` cache. Do not return a cached mutable `DateFormatter` for
unprotected use. A wholesale FormatStyle rewrite needs output-equivalence and performance evidence;
the existing formatter reuse was measured and is not itself a defect.

Do not hold a lock across an `await`, continuation resumption, arbitrary UI work or process termination.
Extract the needed value, then act outside the lock. Mutex is nonrecursive: check for nested acquisition
and maintain a consistent lock order. Short state access is the normal case.

SnippetRepository is a special transaction boundary: the directory lock intentionally spans filesystem
revalidation and mutation. Preserve that scope on its off-main worker until an alternative proves the
same lost-update/conflict behavior. Do not shorten it to a dictionary lookup merely to make the lock
look smaller. Moving the repository to Service is M01, a separate mechanical change.

## S02 — Reduce AppKit transfer assertions selectively

Inventory:

- [IconCache](../../Tinycast/Platform/Images/IconCache.swift#L76): two cache subclasses and a decoded
  result; [ThumbnailCache](../../Tinycast/Platform/Images/ThumbnailCache.swift#L4).
- [ImageThumbnail.Decoded](../../Tinycast/Platform/Images/ImageThumbnail.swift#L20).
- [ExtensionIconCache](../../Tinycast/Features/Extensions/Service/ExtensionIconCache.swift#L9): its own
  cache and decoded result, retained inside Extensions.

Thread-safe cache operations do not establish that every cached `NSImage` is safe to mutate or use
from arbitrary executors. Audit whether a reference is ever modified after publication. Where it
reduces complexity, decode to a compiler-accepted immutable representation off-main and construct
the AppKit object on the main actor. Verify actual SDK conformance rather than asserting that every
CoreGraphics reference is automatically Sendable.

Preserve decoded memory cost, downsampling, appearance keys, warm-row performance and preview purge.
Avoid extra image copies or locking a thread-safe NSCache unnecessarily. An immutable transfer box or
NSObject-based delegate can remain a narrow documented exception when the SDK cannot express its
invariant. The goal is checked mutable-state ownership, not zero appearances of `@unchecked`.

## S03 — SDK imports

[Permissions](../../Tinycast/Platform/Permissions.swift#L5),
[AccessibilityText](../../Tinycast/Platform/AccessibilityText.swift#L3),
AX window/menu services, DictationInsertionContext and HyperKeyTap use `@preconcurrency` around mutable
C globals that function as constant keys. Their comments explain the current reason.

On Swift 6.4, test removing one suppression in isolation. Keep raw pointer access local and snapshot
SDK constants where already appropriate. If the SDK still exposes incorrectly annotated globals,
retain the narrow import with its actual reason. Do not compensate with broad target warning
suppression, extra unsafe state, or a homemade actor bridge.

## Validation and completion

Run `calc-test`, `calc-performance` using its documented benchmark command, `snippets-test`,
`ext-test`, `installed-ai-test`, `updates-test`, `icon-cache-test` and relevant output/stop tests, then
the full suite and build. Add concurrent exactly-once or conflict tests where the synchronization
contract changes. Use Thread Sanitizer for mutable callback boundaries; verify memory and thumbnail
latency for image changes.

Done when migrated state cannot be accessed without its lock, manually unsafe globals are removed
where possible, and every retained unchecked boundary has a narrow ownership proof. Revert one holder
at a time if it causes deadlock, output changes, allocation growth or lost transaction ordering.
