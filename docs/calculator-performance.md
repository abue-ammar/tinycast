# Calculator optimization: implementation and comparison

The advanced calculator retains its features with one typed evaluator, compact unit data and less
work per query. Compared with the previous advanced branch, linked calculator code/data shrank
16.4%, arithmetic improved 44.1%, and unit evaluation improved 32.0%.

The whole Release bundle saves **81,552 bytes (0.69%)**. Advanced features now add **35,040 bytes**
over local main, down from **116,592 bytes**: **70.0% less incremental bundle overhead**. The calculator
is only part of the app, so its percentage reduction is larger than the whole-bundle reduction.

## Plan and implementation

1. Establish pinned main and advanced baselines and measure full evaluation, including formatting.
2. Consolidate scalar and quantity arithmetic into `CalcExpressionParser` and `CalcValue`;
   move operator identity and precedence into `CalcOperator`, functions into `CalcMath`, and keep
   card formatting in `CalcQuantity`.
3. Share immutable `UnitDef` instances across aliases and values. Store 148 base definitions as
   compact catalog records, retaining prefix expansion and every existing conversion factor.
4. Scan Unicode scalars, reject bare ASCII searches before setup, avoid calendar parsing without
   moment signals, share numeric date parsing, and format exact integers without format strings.
5. Verify behavior, run the full project checks, and repeat matching Release measurements.

[Numen's lexer](https://github.com/vicinaehq/numen/blob/36338ae87a8dfbdd0869d70eb6e7cd6c9c8f8771/src/numen/lexer.hpp)
and [value representation](https://github.com/vicinaehq/numen/blob/36338ae87a8dfbdd0869d70eb6e7cd6c9c8f8771/src/numen/value.hpp)
informed the token/value separation. The implementation remains native Swift with Foundation and no
new dependency or bundled timezone database.

Spoken roots now accept measurements (`square root of 25m2` → `5 m`, `cube root of -8m3` → `-2 m`).
Dimensionless unit expressions can feed base conversion (`2m / 2m to hex` → `0x1`).
The clock and calendar are supplied at the UI boundary rather than read from the model.

## Measured tradeoffs

- Warm timezone queries measured 4.2% slower (0.345 µs/query). Date queries improved 2.6%, but remain
  slower than main. These paths retain Foundation calendar and timezone behavior.
- First unit evaluation increased from 1.112 ms to 1.231 ms; compact catalog decoding runs once.
  Warm unit evaluation is 32.0% faster. Cold arithmetic and app-search rejection both improved.
- An `-Osize` experiment saved another ~28 KB in the standalone probe but slowed broad workloads.
  The shipped configuration keeps `-O`; there is no whole-app optimization change hiding in the result.
- Main's 9.805 MB executable already exceeds the documentation's historical 5 MB target. This change
  reduces the executable to 9.840 MB from advanced's 9.921 MB; unrelated features remain in scope of
  that existing size budget.

## Verification

- All **58 harnesses** passed; calculator harness: **1,014 assertions**, zero failures.
- A differential corpus of **3,691 queries** preserved every previously supported result, including
  expression echo, badges, display and copy text. Its three differences are newly supported
  dimensionless unit-to-hex conversions. Additional regression cases cover the spoken unit roots.
- All **675 unit aliases**, labels, dimensions and Double scale/offset bit patterns matched advanced.
- Debug and all three Release builds succeeded. No new compiler warnings; Xcode's existing
  AppIntents metadata notice remains. Lint passed with no new warnings; model import purity and
  `git diff --check` passed.
- No view styling or geometry changed. Validation exercised result payloads and builds; no manual
  visual sweep was performed.

## Reproduce

Check out this implementation and run:

```sh
node Scripts/benchmark-calculator.mjs \
  --main a9c170803a12340539e45ce6a471fa9bd18bb893 \
  --advanced 01f2c2afb1addc172b6b253430008017e7aefcdc \
  --build --runs 9 --iterations 2000
```

The script writes `build/calculator-comparison/report.md`, raw samples and complete outputs in
`results.json`, and Release build logs. Its scratch directory holds the exported revisions,
benchmark executables and derived data. Use a fresh scratch directory when rerunning experiments.

“Main” below means local `main` at `a9c1708`, the ancestor used for the feature comparison.
The locally known `origin/main` has the same calculator sources; the revisions differ only in
window layout settings. Current means this implementation; its pre-commit benchmark was based on advanced
plus the working-tree changes.

## Measurements

Apple M4 Pro; macOS 27.0.

Swift 6, arm64, -O, whole-module optimization; 9 rotating sequential runs, 2000 iterations per query.
Fixed clock, calendar, locale, region and exchange rates. Full engine evaluation includes formatting; CalcMemo is bypassed.

| Metric (bytes) | Main | Old advanced | Current |
| --- | ---: | ---: | ---: |
| Release bundle | 11,687,949 | 11,804,541 | 11,722,989 |
| Release executable | 9,804,696 | 9,921,288 | 9,839,736 |
| Calculator linked symbols | 396,488 | 511,392 | 427,771 |
| Stripped engine probe | 382,032 | 499,904 | 436,480 |
| Model source | 171,368 | 214,031 | 201,548 |

Calculator symbols include Model, Service and UI objects; shared compiler helpers and alignment are not fully attributable.
The standalone probe includes its benchmark driver and is not the calculator's exact contribution to the app.

| Query group (µs/query) | Main | Old advanced | Current | Change vs advanced |
| --- | ---: | ---: | ---: | ---: |
| search | 2.041 | 2.387 | 1.092 | -54.3% |
| arithmetic | 6.303† | 5.979 | 3.344 | -44.1% |
| units | 9.244 | 11.460 | 7.795 | -32.0% |
| currency | 7.012 | 9.135 | 5.774 | -36.8% |
| dates | 11.352 | 12.777 | 12.439 | -2.6% |
| zones | 7.854 | 8.262 | 8.607 | 4.2% |
| partial | 8.953† | 7.915 | 4.423 | -44.1% |
| advanced | 5.937* | 10.257 | 6.802 | -33.7% |

*Main produces different or unsupported answers in this group; its timing is not a like-for-like speed comparison.
†Main calculates the same values; expression echo formatting differs.
Current and advanced benchmark outputs match, including display, copy text, errors and badges.

| First evaluation in fresh process (µs) | Main | Old advanced | Current |
| --- | ---: | ---: | ---: |
| safari | 24.3 | 157.8 | 9.6 |
| 2+2 | 106.5 | 104.6 | 70.1 |
| 10kg + 500g to lb | 1001.6 | 1112.1 | 1231.3 |
| time in Tokyo | 1720.0 | 1704.9 | 1733.0 |

Cold timings exclude process launch and fixture setup; each sample starts a fresh process.

- main: a9c170803a12340539e45ce6a471fa9bd18bb893
- advanced: 01f2c2afb1addc172b6b253430008017e7aefcdc
- current: 01f2c2afb1addc172b6b253430008017e7aefcdc plus working-tree changes
