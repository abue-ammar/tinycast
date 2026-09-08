# Extension menu HTTP retention — 8 September 2026

Repeated Usage menu openings retained HTTP sessions after their Swift owners were released. The fix
in `15cf84b` reuses one private fetcher across extension bridges and explicitly invalidates its
`URLSession` when the fetcher is released. Menu execution contexts remain independent.

## Cause and isolation

Each `ExtensionHostBridge.scoped(to:)` used to allocate another fetcher/session. Runtime teardown
released the bridge and fetcher, but did not invalidate the underlying session. Real HTTP traffic
exposed retention that a custom `URLProtocol` fixture did not reproduce.

A separate localhost probe made 100 requests, each through a new ephemeral session, and retained only
weak references afterward. After ten seconds, all 100 session objects were still alive. Setting
`urlCache = nil` alone did not release them. Explicit invalidation reduced the live-session count to
zero. Reusing one private session also avoided repeatedly creating networking resources.

This establishes HTTP-session retention in the measured workload, rather than proving an indefinitely
growing JavaScript leak. The menu runtime's weak references already cleared after every close.

## Fix

- Scoped bridges reuse the parent bridge's `ExtensionFetcher`, owned within the existing Extensions
  ownership tree. No singleton, actor, core service or persistent JavaScript context was added.
- The fetcher's destructor calls `invalidateAndCancel()`. Discarding a temporary fetcher now releases
  its networking resources as well as its Swift wrapper.
- The private ephemeral configuration disables URL caching, cookie storage and credential storage.
  Request headers and task cancellation remain specific to each request.

Apple documents that [session invalidation](https://developer.apple.com/documentation/foundation/urlsession/invalidateandcancel())
cancels outstanding requests and breaks session delegate/callback references. In-flight extension
requests are already owned by runtime tasks, whose cancellation propagates to `URLSession`.

## Regression coverage

`Tests/ext-fetch-test.swift`, included in `ext-test`, talks to a local Node HTTP server. The server
keeps idle connections open for 60 seconds; releasing a fetcher must close them within the test's
three-second deadline. The fixture also checks overlapping requests: cancelling one must leave the
other functional, and a later request must inherit neither authorization headers nor response cookies.

Against the old fetcher from `194f6ce`, both connection-cleanup assertions fail while five other checks
pass. With the fix, all seven pass. The complete 58-harness suite passes, lint passes with existing
warnings, the model-import check is empty, and Debug builds introduce no new warnings.

```sh
./Scripts/run-tests.sh ext-test
```

## Usage menu stress results

Measured on an M4 Pro with 24 GiB RAM, macOS 27.0 beta (26A5425a), using optimized arm64 harnesses
compiled with Xcode 26.6 and the macOS 26.5 SDK. The baseline is `194f6ce`; the fixed transport is
`15cf84b`. Each variant ran in a fresh process with the same installed OpenCodex Usage extension and
real local proxy requests.

| Variant | Menu cycles | Footprint after first close | After final close | Final idle footprint | Peak footprint |
|---|---:|---:|---:|---:|---:|
| Before fix | 30 | 22.47 MiB | 32.67 MiB | 32.67 MiB | 39.97 MiB |
| Explicit cleanup, separate fetchers | 30 | 21.80 MiB | 25.28 MiB | 24.00 MiB | 34.09 MiB |
| Fix: owned shared transport | 100 | 22.56 MiB | 22.36 MiB | 22.22 MiB | 30.94 MiB |

All 100 fixed-run runtimes released after closing. The median closed footprint in each ten-cycle
block was 23.25, 23.84, 23.70, 19.53, 19.49, 19.53, 23.87, 21.82, 21.88 and 23.31 MiB. The floor
fluctuated rather than accumulating. These measurements support removing the observed retention;
they do not establish that every extension or every long-running workload is leak-free.

The harness uses the shipped runtime, menu manager, controller and fetcher, with a small host stub
that supplies the same shared-fetcher ownership as the production bridge. It runs a native AppKit
event loop, invokes menu lifecycle delegates, performs Refresh on every second close, and leaves
the final menu open for 15 seconds before a 15-second closed idle period. Status items are hidden;
this does not measure popup tracking or compositor performance. Numbers are the isolated harness's
physical footprint, not full-app RSS. Each variant has one stress run, so small differences are noise.

Raw observations, localhost probes, compilation commands, CSV data and charts are stored locally in
the ignored `build/benchmarks/2026-09-08-menu-memory-fix/` directory. The preceding main-versus-branch
comparison remains in `build/benchmarks/2026-09-08-menu-bar/`; its baseline results were preserved.
