# Calculator optimization: implementation and comparison

The advanced calculator retains its features with one typed evaluator, compact unit data and less
work per query. Compared with the previous advanced branch, linked calculator code/data shrank
16.3%, arithmetic improved 43.6%, and unit evaluation improved 36.5%.

The whole Release bundle saves **81,632 bytes (0.69%)**. Advanced features now add **34,960 bytes**
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

## Second review pass

The follow-up review checked parsing, numeric limits, token reconstruction, Unicode whitespace,
conversion routing and the size/speed tradeoffs of the first implementation (`4854ede`). It found and
fixed four correctness gaps:

- Overflowing compact literals such as `1e308k` no longer show `inf`.
- Non-finite intermediate arithmetic cannot become a boolean or disappear through a later power.
- A trailing operator preserves conversion precision: `1.00000000004m to pm +` now keeps
  `1000000000040 pm`, matching the complete conversion.
- Binary and octal literals carry their own source badges, including while typing an operator.

`CalcNumberBase` centralizes names, prefixes and conversion targets. Checking the target before
evaluating radix input removes redundant parsing from unit and currency conversions. Timezone routing
shares its initial word split between connector and suffix checks, removing per-character string growth.
A first timezone simplification measured slower and was replaced before shipping.

An expanded differential corpus of **3,998 queries** had 66 changes against the first pass: 20 precision
fixes, 14 overflow rejections and 32 radix-badge fixes, with no other differences. A separate seeded
reference check covered **5,000 arithmetic and unit expressions** using Python rational arithmetic;
every result matched within display precision, and exactly representable integers copied exactly.

The Release bundle is effectively unchanged from the first pass: **11,722,989 → 11,722,909 bytes**
(80 bytes smaller). Linked calculator symbols increased by 260 bytes; the added checks and base metadata
fit within the existing footprint once shared helpers and alignment are included.

A separate paired comparison used nine alternating sequential runs, 2,000 iterations per query, and
the same compiler, driver and fixtures. This avoids comparing timings from different measurement sessions.

| Query group (µs/query) | First pass (`4854ede`) | Reviewed | Change |
| --- | ---: | ---: | ---: |
| search | 1.121 | 1.139 | +1.6% |
| arithmetic | 3.447 | 3.428 | -0.5% |
| units | 8.066 | 7.531 | -6.6% |
| currency | 5.959 | 5.655 | -5.1% |
| dates | 12.772 | 12.688 | -0.7% |
| zones | 8.770 | 8.769 | approximately unchanged |
| partial | 4.472 | 4.579 | +2.4% |
| advanced | 6.977 | 6.723 | -3.6% |

Search rejection and partial expressions measured 0.018 µs and 0.107 µs slower respectively.
All benchmark outputs matched the first pass; the corrected edge cases are covered separately above.
To reproduce this timing comparison with the committed driver, pass `--advanced 4854ede` and omit
`--build`; the three-version main/advanced comparison below uses the original advanced baseline.

## Measured tradeoffs

- Warm timezone queries measured 4.1% slower (0.359 µs/query). Date queries improved 2.2%, but remain
  slower than main. These paths retain Foundation calendar and timezone behavior.
- First unit evaluation increased from 1.123 ms to 1.264 ms; compact catalog decoding runs once.
  Warm unit evaluation is 36.5% faster. Cold arithmetic and app-search rejection both improved.
- An `-Osize` experiment saved another ~28 KB in the standalone probe but slowed broad workloads.
  The shipped configuration keeps `-O`; there is no whole-app optimization change hiding in the result.
- Main's 9.805 MB executable already exceeds the documentation's historical 5 MB target. This change
  reduces the executable to 9.840 MB from advanced's 9.921 MB; unrelated features remain in scope of
  that existing size budget.

## Verification

- All **58 harnesses** passed; calculator harness: **1,035 assertions**, zero failures.
- The first pass compared **3,691 queries** against advanced, with three newly supported unit-to-hex
  conversions. The second pass added the checks and intentional correctness fixes described above.
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
  --build --runs 9 --iterations 2000 --output build/calculator-review
```

This command writes `build/calculator-review/report.md`, raw samples and complete outputs in
`results.json`, and Release build logs. Its scratch directory holds the exported revisions,
benchmark executables and derived data. Use a fresh scratch directory when rerunning experiments.

“Main” below means local `main` at `a9c1708`, the ancestor used for the feature comparison.
The locally known `origin/main` has the same calculator sources; the revisions differ only in
window layout settings. Current means the reviewed implementation, measured from first-pass commit
`4854ede` plus the working-tree changes in this review commit.

## Measurements

Apple M4 Pro; macOS 27.0.

Swift 6, arm64, -O, whole-module optimization; 9 rotating sequential runs, 2000 iterations per query.
Fixed clock, calendar, locale, region and exchange rates. Full engine evaluation includes formatting; CalcMemo is bypassed.

| Metric (bytes) | Main | Old advanced | Current |
| --- | ---: | ---: | ---: |
| Release bundle | 11,687,949 | 11,804,541 | 11,722,909 |
| Release executable | 9,804,696 | 9,921,288 | 9,839,656 |
| Calculator linked symbols | 396,488 | 511,392 | 428,031 |
| Stripped engine probe | 382,032 | 499,904 | 436,368 |
| Model source | 171,368 | 214,031 | 201,223 |

Calculator symbols include Model, Service and UI objects; shared compiler helpers and alignment are not fully attributable.
The standalone probe includes its benchmark driver and is not the calculator's exact contribution to the app.

| Query group (µs/query) | Main | Old advanced | Current | Change vs advanced |
| --- | ---: | ---: | ---: | ---: |
| search | 2.127 | 2.496 | 1.173 | -53.0% |
| arithmetic | 6.641† | 6.276 | 3.540 | -43.6% |
| units | 9.748 | 12.145 | 7.709 | -36.5% |
| currency | 7.374 | 9.562 | 5.805 | -39.3% |
| dates | 11.804 | 13.306 | 13.014 | -2.2% |
| zones | 8.233 | 8.665 | 9.024 | 4.1% |
| partial | 9.488† | 8.246 | 4.722 | -42.7% |
| advanced | 6.269* | 10.693 | 6.950 | -35.0% |

*Main produces different or unsupported answers in this group; its timing is not a like-for-like speed comparison.
†Main calculates the same values; expression echo formatting differs.
Current and advanced benchmark outputs match, including display, copy text, errors and badges.

| First evaluation in fresh process (µs) | Main | Old advanced | Current |
| --- | ---: | ---: | ---: |
| safari | 26.2 | 157.6 | 9.3 |
| 2+2 | 106.0 | 109.0 | 69.0 |
| 10kg + 500g to lb | 1021.3 | 1123.3 | 1264.4 |
| time in Tokyo | 1747.1 | 1740.4 | 1721.1 |

Cold timings exclude process launch and fixture setup; each sample starts a fresh process.

- main: a9c170803a12340539e45ce6a471fa9bd18bb893
- advanced: 01f2c2afb1addc172b6b253430008017e7aefcdc
- current: 4854ede57d5c174701107abea5e36545eccd26b1 plus working-tree changes
