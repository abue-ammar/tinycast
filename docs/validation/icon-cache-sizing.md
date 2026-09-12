# Layout-sized launcher file icons — #568

The launcher list and compact favorites retain a bitmap sized for the selected layout and display
scale. Settings and other callers retain the existing 96px path. Symbols, extension artwork and
fitted previews are unchanged. The source is still rasterized through the original 48pt-at-2×
context before reduction; directly selecting a smaller NSWorkspace representation is deliberately
avoided because it previously changed icon shadows and corners.

## Measurement

Measured 2026-09-12 on Apple M4 Pro, macOS 26.6.2 (25G83), Swift 6 with `-O`, based on
upstream `8b3f80239109af988f788b3c534ce3629aaafa56`. The standalone probe compiles the shipped
`IconCache.swift`; size `0` exercises its unchanged default 96px path, and 24/26/29 exercises the
new row path. Three fresh processes per case, alternating order: 100/500 retained entries and a
500-entry Default → Large → Larger → Default transition (30 processes in total).

Each workload cycles six built-in app icons under independent stamped keys. This isolates bitmap
retention, not the icon diversity of 500 different installed apps. No JavaScript engine, extension,
clipboard capture, settings store or AppCore is started. A small warm-up precedes the measurement.
The row cache holds only the final bitmap and charges `bytesPerRow * pixelsHigh`, including padding.

| 500 retained entries | Bitmap allocation | Process physical footprint, median (range) | Cold generation, median | Warm lookups, median |
| --- | ---: | ---: | ---: | ---: |
| Existing 96px | 17.58 MiB | 30.95 (30.86–31.00) MiB | 180.11 ms | 0.110 ms |
| Default: 48px | 4.39 MiB | 15.81 (15.70–16.09) MiB | 198.89 ms | 0.114 ms |
| Large: 52px | 5.55 MiB | 15.91 (15.63–15.94) MiB | 192.21 ms | 0.118 ms |
| Larger: 58px | 7.08 MiB | 15.66 (15.64–16.06) MiB | 201.20 ms | 0.113 ms |

The bitmap reductions are 75.0%, 68.4% and 59.7%; measured held-process reduction is about
15.0–15.3 MiB for 500 entries, or 2.9–3.0 MiB for 100 entries. These are **cache-probe results,
not whole-app RAM savings or package-size reductions**. Warm times cover all 500 lookups.
Cold medians increase by 12–21 ms over all 500 entries because of the second rendering step.

| Probe lifecycle, 500 entries | Existing 96px | Default | Large | Larger |
| --- | ---: | ---: | ---: | ---: |
| Before loading | 6.95 MiB | 7.14 MiB | 7.25 MiB | 7.02 MiB |
| Icons held | 30.95 MiB | 15.81 MiB | 15.91 MiB | 15.66 MiB |
| Purged, references released, settled 1s | 7.53 MiB | 8.00 MiB | 8.11 MiB | 7.86 MiB |

These are sampled `TASK_VM_INFO.phys_footprint` values, not maximum-resident-set or continuous peak
measurements. The allocator does not immediately return every page after an image is released.
Weak references confirm that the sampled image and bitmap release after purge and caller release.
Replacing rows incrementally across all sizes stayed within 16.11–16.74 MiB in the transition runs;
unsized requests reused the original objects and stayed within 31.09–31.42 MiB.

[Raw measurements and source hashes](icon-cache-sizing.json) preserve all repeats.

## Validation and limits

- All 70 upstream harnesses passed; the expanded icon-cache harness also passed after formatting.
- Debug build succeeds with no new compiler warnings. The existing AppIntents metadata warning
  remains. Lint exits 0; changed files have no lint warnings. Model purity and `git diff --check` pass.
- 72 offscreen comparisons match baseline final-size bytes: six built-in icons × three layout sizes
  × two scales × Aqua/Dark Aqua. These do not substitute for physical-display or native video testing.
- A fixture linking the actual Debug `AppIconView` passed eight live layout/scale changes plus visible
  style invalidation. Display-scale overrides exercise view requests, not the Mac's display settings.
- The Dev build was opened for user review, and the user approved proceeding with the PR. No matched
  native before/after video is attached; further visual verification is requested from the maintainer.
- `leaks --atExit` reports 287 allocations in both probe runs: 18,720 bytes baseline and 18,768 bytes
  candidate. Both reports point to three AppIntents/LinkServices NSXPCConnection root cycles and
  warn that the process is not debuggable. This is **not a zero-leak result or a whole-app leak audit**.
  The cache's weak image/bitmap release assertions pass in both runs.
- Full-app idle/open/peak/closed memory has not been measured for this exact branch. Those numbers
  cannot be inferred from the cache probe or the earlier experiment on #568.

A row cache slot contains only one requested size. A late decode may replace a newer size's cache
slot, but size validation prevents it being served for the wrong request and cancelled SwiftUI tasks
cannot update the visible row. A subsequent miss regenerates the correct size. A style change also
prevents an old-generation decode from publishing. The existing 96px cache remains separate, so
Settings and a launcher row can safely coexist; retaining both reduces the net memory benefit.
NSCache eviction remains advisory, and externally held images survive it.

## Reproduce

From the repository root with the Xcode 26 toolchain selected:

```sh
./Scripts/run-tests.sh
./Scripts/lint.sh
mkdir -p build/icon-cache-sizing
xcrun swiftc -swift-version 6 -O -parse-as-library \
  Tinycast/Platform/Appearance.swift Tinycast/Platform/Images/IconCache.swift \
  Tests/icon-cache-memory.swift -o build/icon-cache-sizing/probe
build/icon-cache-sizing/probe 0 500
build/icon-cache-sizing/probe 24 500
build/icon-cache-sizing/probe 26 500
build/icon-cache-sizing/probe 29 500
build/icon-cache-sizing/probe 24 500 switch
leaks --atExit -- build/icon-cache-sizing/probe 0 500 switch
leaks --atExit -- build/icon-cache-sizing/probe 24 500 switch
```

Repeat the probe commands in fresh processes; use count 100 for the smaller workload. It reads only
built-in app icons, does not start Tinycast services, and asserts warm object reuse and release.
