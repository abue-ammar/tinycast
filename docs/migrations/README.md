# Modern macOS and Swift migration audit

Audited on **2026-10-09**, against commit `16a939726e8ed5e6ae2e2a47256d0722c3f826b2`.
These are proposed migrations; this audit changes documentation only.

Tinycast already has a strong foundation: macOS 26.0 deployment, Swift 6 language mode,
complete concurrency checking, Observation, one composition root, and native AppKit surfaces.
The worthwhile work is to strengthen the remaining concurrency boundaries, replace superseded APIs,
and bring the implemented layers into line with the engineering rules.

## Target and interpretation

The requested baseline is **macOS 26+ with a Swift 6.4 compiler**. The local toolchain is Xcode 27.0
(`27A266a`), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), using the macOS 27 SDK. The project's deployment
target remains 26.0. Compiler version, language mode, SDK version and deployment target are separate
choices. `SWIFT_VERSION: "6.0"` correctly selects Swift 6 language mode; changing it to `"6.4"` is not
the compiler migration. Apple's [Xcode requirements](https://developer.apple.com/xcode/system-requirements)
and [Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/) establish that distinction.

The repository's Xcode 26 wording and release workflow need updating to guarantee the requested
compiler. Raising the deployment target to 27 is outside this plan. A future decision to support
only macOS 27 would allow additional runtime APIs; it should be a separate explicit platform change.

Findings use three evidence levels:

- **Confirmed:** the source or build settings contain the described pattern.
- **Inferred risk:** the pattern permits a problematic execution path, but this audit did not reproduce
  a user-visible failure or capture a data race.
- **Investigation:** availability, feature parity or a behavior decision must be resolved before a
  replacement can be specified safely.

An old spelling, an unsafe conformance, and an SDK deprecation are different findings. Counts below
identify review surfaces; they are not counts of bugs.

## Plans

Difficulty estimates include focused implementation and validation for one experienced contributor.
**Low** is usually up to two days, **Medium** several days, and **High** a week or more. They are planning
ranges, not commitments. Risk measures possible behavior, data or lifetime regressions, independently
of difficulty. Each plan rates its individual work items.

| Plan | Main work | Difficulty | Risk |
| --- | --- | --- | --- |
| [01 — Toolchain and validation](01-toolchain-and-validation.md) | Guarantee Swift 6.4; compile harnesses for the app's deployment target | Low–High | Low–High |
| [02 — Actor boundaries and notifications](02-actor-boundaries-and-notifications.md) | Typed workspace messages; synchronous callback isolation; KVO boundaries | Medium | Medium–High |
| [03 — Tasks, Observation and timers](03-tasks-observation-and-timers.md) | Owned observation loops, cancellable delays, explicit background execution | Medium | Medium–High |
| [04 — Synchronization and Sendable](04-synchronization-and-sendable.md) | State-owning `Mutex`; reduce manually asserted thread safety | Low–Medium | Low–Medium |
| [05 — Subprocesses and extension runtime](05-subprocess-and-runtime.md) | Suspending exit waits, pipe backpressure, cancellation, JS confinement | Medium–High | Medium–High |
| [06 — Camera and Dictation capture](06-capture-isolation.md) | Serialize session operations; exactly-once photo completion; preserve audio confinement | Medium–High | High |
| [07 — Model purity and main-actor I/O](07-model-purity-and-io.md) | Move effects to Service; inject environment facts; protect UI latency | Low–High | Medium–High |
| [08 — macOS APIs and compatibility](08-macos-api-and-compatibility.md) | Modern activation; evaluate legacy formats, private APIs and pasteboard access | Low–Medium | Low–High |
| [09 — SwiftUI ownership and TextKit](09-swiftui-and-textkit.md) | Direct coordinator injection; migrate chat rendering to TextKit 2 | Medium–High | Medium–High |

## Recommended sequence

**P1** means do first; **P2** means scoped follow-up; **P3** means optional cleanup or a decision first.
P1 here is modernization priority, not an assertion of a reproduced critical bug.

1. **T01/T02:** establish the compiler and minimum-target validation before changing execution rules.
2. **O08/O01/O07/S01:** remove the NSAlert violation, modernize activation/pickers and migrate small
   lock-backed state holders separately.
3. **A01:** migrate workspace notifications using the macOS 26 typed APIs. Preserve synchronous delivery.
4. **P03/P01/P02:** fix process timeout ownership, blocking AI probes, and MCP pipe writes in separate PRs.
5. **C01/C02:** address camera operation overlap and photo completion. Include real hardware checks.
6. **L03/A02:** migrate delayed paste delivery and synchronous event callbacks with focused regressions.
7. **L01/L02/L04/M01/M02/V01:** simplify observation, polling, task execution, layering and dependencies.
8. **M03/P04/V02:** measure storage, prove JS-runtime confinement and migrate chat's text layout independently.
9. Resolve **O02/O03/O04/O05** as explicit behavior or API-parity decisions before deleting any path.

Do not bundle these into a repository-wide rewrite. A PR should change one lifetime or platform
boundary so its behavior and rollback remain understandable.

## Scan inventory

Scanned 779 non-generated Swift files under `Tinycast/`, with targeted reads of services, models,
views, harnesses, project settings, workflows and feature invariants. Counts exclude lines beginning
with Swift comments; multiline `@unchecked Sendable` declarations are included.

| Pattern | Occurrences | Files | Interpretation |
| --- | ---: | ---: | --- |
| `@Observable` | 77 | 77 | Modern observation is already established |
| `ObservableObject` in source | 0 | 0 | No wholesale Observation migration needed |
| `MainActor.assumeIsolated` | 35 | 17 | Runtime assertions deserve boundary-specific replacement/review |
| `@unchecked Sendable` | 22 | 15 | Some wrappers are justified; mutable capture/runtime state deserves priority |
| `nonisolated(unsafe)` | 2 | 2 | Formatter cache and extension delegate |
| `Task.detached` | 80 | 49 | Mix of valid background work, blocking I/O and cleanup bookkeeping |
| `DispatchQueue` references | 21 | 13 | Includes necessary blocking-I/O and SDK callback queues |
| `NSLock()` | 7 | 6 | Existing `Synchronization.Mutex` usage provides a local migration precedent |
| `withObservationTracking` calls | 7 | 6 | Manually rearmed will-set observation |
| `Timer.publish` | 3 | 3 | Permissions, Quick Actions and Onboarding |
| `NSApp.activate(ignoringOtherApps:)` | 23 | 16 | Superseded activation request |
| `runModal()` | 16 | 12 | Fifteen filesystem picker calls and one NSAlert loop |

Useful repeatable searches, run from the repository root:

```sh
rg -n 'MainActor\.assumeIsolated|@unchecked|nonisolated\(unsafe\)|@preconcurrency' Tinycast --glob '*.swift'
rg -n 'Task\.detached|DispatchQueue|DispatchSemaphore|NSLock\(|Timer\.publish' Tinycast --glob '*.swift'
rg -n 'withObservationTracking|activate\(ignoringOtherApps:|NSFilenamesPboardType' Tinycast --glob '*.swift'
rg -n 'FileManager|Data\(contentsOf|NSHomeDirectory|ProcessInfo|Date\(\)' Tinycast/Features/*/Model/
```

Source anchors in these plans refer to the audited commit and will move as work lands.

## What should stay

- AppKit panels, responders, delegates, hosting views, `NSTableView` and the accessory app lifecycle
  are appropriate native APIs. Their age alone does not justify replacement with SwiftUI scenes.
- Carbon hotkey registration and HIToolbox input-source APIs are documented capability gaps. Keep them
  unless a public replacement actually provides the same behavior.
- Dispatch filesystem sources and AVFoundation sample-buffer queues are real platform boundaries.
  Improve ownership and confinement; do not replace them with polling or per-buffer tasks.
- `NotificationToken` correctly removes block observers. Replace a call site with native typed
  observation where available; avoid an extra generic observation framework.
- Cacheless ephemeral network sessions, generated assets, the Debug channel, and the sole `AppCore`
  owner remain constraints. Keep extension-specific UI and runtime work inside Extensions.
- `EdgeDissolve.swift` and `ThinScrollbar.swift` remain off-limits. Their queue usage is counted, but
  no migration in this audit authorizes edits to those files.
- Span, noncopyable collections, typed throws everywhere, new actors and extra caches are not automatic
  quality improvements. Adopt a feature only when it simplifies a measured or demonstrated problem.

## Baseline verification

| Check | Result on the unchanged application code |
| --- | --- |
| `./Scripts/run-tests.sh` | All 94 harnesses passed in 93 seconds |
| Unsigned Debug build, Xcode 27 / Swift 6.4 | Passed; no Swift deprecation or concurrency diagnostics |
| Build warnings | One App Intents metadata-extraction warning because no AppIntents dependency exists |
| `./Scripts/lint.sh` | Passed; existing warning-level violations remain |
| AppKit/SwiftUI/Cocoa imports under `Features/*/Model/` | No matches |
| macOS 26-targeted API probes | `Mutex`, typed workspace observation, `Observations`, `@concurrent`, async `defer` and async NSOpenPanel presentation typechecked with warnings as errors |
| macOS 27-only API probes | Compiler rejected cancellation shielding and advanced observation tracking at target 26.0, as expected |

The initial sandboxed build failed during Icon Studio export; the build passed with macOS service
access. SwiftLint initially could not save its cache; rerunning with cache access passed. Those were
environment failures, not application defects.

The full app build used an explicit deployment target from the project. The existing standalone
harness runner does not specify that target; T02 addresses that gap. No Release build, actual macOS 26
runtime run, interactive UI regression sweep, hardware capture test, Thread Sanitizer run, Instruments
trace or leak measurement was performed. Passing automation does not prove the inferred races or
performance problems, or make the future migrations merge-ready.

## Completion bar for each migration

Use [testing.md](../testing.md) and the affected feature's invariants. Preserve behavior, pass the full
suite and lint, build without new warnings, keep Model imports clean, update affected docs in the same
commit, and perform the relevant UI/hardware checks. Validate cancellation and stale results where a
lifetime changes. Measure UI latency and memory where an executor, storage or layout changes; retain
the existing under-100 MB budget and return-to-baseline requirement.

The desired result is a small native app whose concurrency guarantees are easy to establish from its
types and owners, with the remaining platform exceptions explicit and narrow.
