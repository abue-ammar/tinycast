# 01 — Swift 6.4 toolchain and validation

Status: proposed. Baseline and sequencing: [audit index](README.md).

## Findings

| ID | Evidence | Priority | Difficulty | Risk |
| --- | --- | --- | --- | --- |
| T01 | [project.yml](../../project.yml#L14) selects Swift 6 correctly, but [development.md](../development.md#L9), [AGENTS.md](../../AGENTS.md#L11) and both Xcode-selection steps in [release.yml](../../.github/workflows/release.yml#L37) still specify Xcode 26 | P1 | Low | Low |
| T02 | [run-tests.sh](../../Scripts/run-tests.sh#L30) compiles with `-swift-version 6` without `-target`; its compile database uses an SDK but also omits the app's target | P1 | Medium | Low |
| T03 | Project settings do not set compiler default isolation or approachable-concurrency behavior; source uses explicit `@MainActor`, `nonisolated` and detached jobs | P2, evaluate after executor audit | High | High |

All three patterns are confirmed. T03 is an explicit-settings/design opportunity, not a strict
concurrency failure. Swift 6 language mode and `SWIFT_STRICT_CONCURRENCY: complete` are already set and
inherited by the application and helpers.

## Migration

For T01, select a stable toolchain supplying Swift 6.4 in local requirements and both release jobs.
The audited local Xcode 27.0 supplies it. Assert the actual compiler version after selection and print
the SDK/build versions in the job log. Keep `SWIFT_VERSION: "6.0"`; do not introduce a fictitious 6.4
language mode. Keep the macOS 26.0 deployment target and XcodeGen ownership. Update any toolchain
instructions that become false in the same change. Apple's
[Xcode requirements](https://developer.apple.com/xcode/system-requirements) distinguish compiler and
language versions.

For T02, compile each harness with an explicit architecture-qualified macOS 26.0 target and the
selected macOS SDK. Produce the same flags in the editor compile database and benchmark commands.
Prefer reading the existing project deployment setting over a new settings subsystem; make mismatches
fail clearly. Continue using standalone harnesses compiling shipped sources. A new SwiftPM or XCTest
architecture is unnecessary.

Run all harnesses with the target change, including macro-using AppKit harnesses and helpers. A host
running macOS 27 otherwise allows a harness to compile an API the application cannot use at 26.0.
Compilation for 26.0 and execution on 27 are still different checks: retain real macOS 26 runtime
verification for platform changes.

For T03, record effective compiler flags first. Review the relevant `nonisolated async` functions and
finish L04/P01/P02 before changing their default behavior. The
[async isolation proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)
introduces explicit `@concurrent` execution and caller-isolated async behavior. A plain `async` or
`nonisolated` spelling must not be used as proof that work leaves the main actor.

Keep explicit UI isolation. If `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is adopted, explicitly
preserve nonisolated pure model types and helper code, and match flags in harnesses. If the change
adds more annotations or hides important boundaries, retaining explicit isolation is a sound outcome.
Treat `SWIFT_APPROACHABLE_CONCURRENCY` separately from default isolation; inspect its effective flags
and adopt deliberately, rather than turning every switch on in one PR. See
[SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md).

## Availability already checked

The installed SDK interfaces and Swift 6.4 typecheck probes at `arm64-apple-macos26.0` establish:

| Facility | Fits macOS 26 baseline? | Implication |
| --- | --- | --- |
| `Synchronization.Mutex` | Yes; available from macOS 15 | Use for short synchronous critical sections |
| `NotificationCenter.MainActorMessage` / `AsyncMessage` | Yes; macOS 26 | Use native typed messages where the notification provides one |
| Typed `NSWorkspace` termination observation | Yes; macOS 26 | Candidate for A01 |
| `Observations` | Yes; macOS 26 | Candidate for L01 |
| `@concurrent` | Yes with the selected compiler | Express finite work's executor explicitly |
| `await` in `defer` | Typechecked for macOS 26 with Swift 6.4 | Simplify asynchronous resource cleanup where semantics fit |
| `withTaskCancellationShield` | No; macOS 27 | Do not use while the floor is 26 |
| Advanced `withObservationTracking(options:_:onChange:)` | No; macOS 27 | Keep it out of a 26-targeted migration |

Swift 6.4's [release notes](https://www.swift.org/blog/swift-6.4-released/) announce async cleanup and
advanced observation; compiler support does not erase the SDK's runtime availability annotations.
Do not add version branches or wrappers to reach 27-only facilities. Supporting only 27 would be a
separate platform decision.

## Validation and rollback

- Verify effective settings for Debug, Release, ClipboardTextHelper and DictationHelper. Regenerate
  the committed project only if `project.yml` changes.
- Run the complete harness suite, lint and an unsigned Debug build. Toolchain changes also require a
  Release build and the release workflow's signing/embedding checks before shipping.
- Check helper identities, entitlements, optimization and generated resources; a compiler update must
  not accidentally change channel isolation or helper packaging.
- Keep default-isolation and async-behavior changes in a later PR, so they can be reverted without
  losing the compiler/target validation improvement.

Done when local, release and harness builds agree on Swift 6.4, Swift 6 mode and the chosen platform
floor, and background work remains explicit under the effective isolation settings.
