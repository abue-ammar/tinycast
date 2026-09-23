# Row icon cache validation

Measured on 2026-09-23, macOS 27.0 (26A428), Xcode 27.0, Apple Silicon.
This compares upstream `main` at `d93a09b` with the row-source repair based on
that commit. The closed PR #858 was measured separately on its older base; its
500-entry test retained 18,432,000 extra bytes of 96px images. It is not used
as the baseline below.

## Isolated cache

`Tests/icon-cache-performance.swift` compiles the shipped `IconCache.swift` with
Swift 6 and `-O`. Each fresh process requests row icons with independent stamps,
cycling six installed system app icons. It reports `task_vm_info` physical
footprint and retained row and 96px cache entries. Compile against each checkout:

```sh
swiftc -O -swift-version 6 Tinycast/Platform/Appearance.swift \
    Tinycast/Platform/Images/IconCache.swift \
    /path/to/Tests/icon-cache-performance.swift -o /tmp/icon-cache-performance
for run in 1 2 3; do /tmp/icon-cache-performance 500 24 2; done
```

Three fresh processes per case; values are median physical footprint in MiB.

| Entries | Row pixels | Current main | Repair | 96px entries, both |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 48 | 7.91 | 7.88 | 0 |
| 500 | 48 | 14.50 | 14.63 | 0 |
| 500 | 52 | 14.63 | 14.61 | 0 |
| 500 | 58 | 14.64 | 14.64 | 0 |

For 500 entries at 48px, both retained 4,608,000 bytes of row bitmap data
and no 96px entries. The 0.13 MiB process difference is smaller than the
variation between fresh runs. These are synthetic cache workloads: 500 keys
cycle six source icons, not 500 distinct installed apps.

## Debug application

Unsigned Debug builds of current main and the repair were launched sequentially
as `Tinycast Dev.app` with the same development-channel settings. The installed
release app was not measured. In each run, the launcher opened at Default size
in light appearance; its list was scrolled down 8 then 15 pages through the
native UI. `footprint -p` readings are rounded to whole MB. The closed reading
was taken 15 seconds after Escape.

| Build | Palette open | After scrolling | Closed, 15 s |
| --- | ---: | ---: | ---: |
| Current main | 57 MB | 71 MB | 73 MB |
| Repair | 52 MB | 69 MB | 76 MB |

Both builds stayed below 100 MB in these spot samples. Neither returned to its
pre-palette footprint after closing. Only one matched application-level run
was completed for each build, so these numbers cannot establish a stable
whole-app difference or a peak bound. The UI automation service stopped a
repeat run after the foreground app changed. `leaks` was not run on these builds.

## Behavior and visual check

- `ZDOTDIR=/tmp TINYCAST_TEST_JOBS=4 ./Scripts/run-tests.sh`: 75/75 passed.
  Without the temporary `ZDOTDIR`, two AI harnesses picked real installed CLIs
  through the user's login-shell configuration instead of their test stubs;
  both failed identically on unmodified current main.
- `icon-cache-test` covers a cold 48px row without a 96px cache entry, warm
  full-size reuse, replacement, and 72 final-size byte comparisons across six
  icons, three sizes, two scales and two appearances.
- Both Debug builds passed with the same existing Clipboard compiler warnings.
  Lint passed with existing warnings; the Model import check and `git diff
  --check` passed.
- Current main and repair were visually inspected at Default/light while
  opening and scrolling the launcher. Earlier testing on the older base checked
  the repair at Default, Large and Larger in light and dark appearance. A
  matched native video was not captured.

## Review

The repair uses a 96px file icon only when that cache is already warm. A
row-only request retains only its smaller row bitmap. If resizing fails, all
bitmap representations are charged to the row cache; a source that cannot be
measured is returned without caching. This addresses the memory regression
raised on PR #858 and the fallback-cost review comment.
