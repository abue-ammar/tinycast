# Clipboard OCR opt-in — maintainer feedback and measurements

Implements the behavior requested in [issue #518](https://github.com/abue-ammar/tinycast/issues/518#issuecomment-5600402867):
local recognition is off by default, ordinary text/path results return immediately, recognized text
stays out of resident clipboard items, and type classification uses original content. There is no OCR
spinner or skeleton. This is a working implementation with remaining acceptance limits below;
Raycast parity and a literal zero-memory-after-disable guarantee are not established.

## How the performance work carries forward

PERF-013/014/015 are local investigation identifiers; their relevant mechanisms and findings
are described here so this report is self-contained.

- PERF-013: retain the bounded original-text FTS query; materialize OCR rows only after
  selecting bounded history row IDs. OCR matching now runs off-main and is cancelled on query/filter
  replacement or dismissal. Matching pins are retained separately, and each active type gets its own
  OCR candidate budget.
- PERF-014: retain `Paster`'s `.mappedIfSafe` image payload read. OCR never rewrites the
  image or changes the value copied/pasted. Its previous copy timings are not OCR extraction timings.
- PERF-015: report RSS and physical footprint separately, including settled phases.
  Do not interpret framework mappings or an isolated lower RSS snapshot as reclaimed application heap.
  No speculative allocator purge or framework teardown was added.

The ordering changes intentionally: matching pins first, then ordinary matches, then OCR-only
unpinned matches within the active type. This keeps ordinary results available while OCR arrives.
It is not output-equivalent to the prototype's combined-recency union. Classification never reads
recognized text: an image containing a URL stays an image, not a Link.

## Search measurements

2026-09-09; Apple M4 Pro, macOS 26.6.2 (25G83), Swift 6.3.3, system SQLite 3.51.0.
The baseline is the saved working-tree OCR prototype with PERF-013/014 already applied, not clean
upstream. Both compile shipped model sources with `swiftc -O -swift-version 6`. Copied PERF-013
synthetic databases contain 1,000 and 100,000 mixed records plus a 100,000-text control. Each variant
runs in three fresh processes, alternating order, with three warmups and 30 measured calls per query.
The search memo is evicted before timing. Compilation, app fixtures and quality checks run separately.

These are store-call/publication timings, not keystroke-to-pixel or complete frame latency.
The table reports medians of process medians; brackets show their range. Every process median/p95,
CPU measurement and source identity is in [the JSON record](clipboard-ocr-opt-in.json).

| 100,000 mixed clips / query | Prototype synchronous, ms | New OCR off, ms | New OCR on: immediate, ms | New OCR on: complete, ms |
| --- | ---: | ---: | ---: | ---: |
| `common` (both sources) | 47.394 [46.791–63.627] | 0.291 [0.281–0.303] | 0.381 [0.359–0.395] | 82.227 [79.230–84.464] |
| `document` (text/path only) | 0.665 [0.551–1.594] | 0.353 [0.347–0.370] | 0.422 [0.404–0.572] | 1.284 [1.205–2.478] |
| `invoice` (OCR only) | 51.066 [50.366–52.904] | 0.060 [0.059–0.062] | 0.100 [0.099–0.103] | 74.832 [74.483–96.231] |

The immediate `invoice` response contains no OCR matches; they arrive at completion. Ordinary
results become available much sooner, but **complete broad OCR search is slower and uses more CPU**.
For `common`, process CPU rises from 47.017 to 76.389 ms per completed query; for `invoice`, from
50.464 to 74.247 ms. The new reader opens per query, uses a 2 MiB SQLite cache budget and releases its
connection afterward; it also preserves all OCR-matching pins without retaining their recognized
strings. No claim is made that all search work becomes cheaper. End-to-end typing/frame measurement
remains open.

## Memory and recognition CPU

A dense standalone load fixture has 1,000 mixed clips, including 666 entries with 31,994 bytes of
recognized text each. Three fresh processes per variant load the same database and settle for one
second. The prototype's median RSS is 46.70 MiB [46.63–46.75], versus 7.27 MiB [7.23–7.28] now;
physical footprint is 42.22 versus 2.78 MiB. This is a stress-case **store-load comparison**, not a
39 MiB saving promised for a normal app. The new store does not load derived strings with its items.

The measurements above and the three app-module fixtures below come from the original working-tree
build, before isolating this contribution on upstream `17ed8a1`. The measured clipboard model,
extractor and indexer sources are identical in the PR; unrelated changes to other features were
excluded. These app aggregates are historical measurements, not measurements of the rebased build.

The three app-module fixtures use the real AppCore, optional indexer, palette and clipboard
coordinator. Each runs in a fresh UUID-scoped sandbox with verified denial of an external canary and
an isolated profile. General clipboard access is redirected in-process to a unique private board.
`AppCore.start`, global capture, hotkeys and optional services never start. The workload recognizes
one 1000×300 PNG and one scanned PDF page through the actual idle worker.

| App-fixture phase | RSS median [range], MiB | Physical footprint median [range], MiB |
| --- | ---: | ---: |
| Cold disabled, settled | 64.25 [59.39–66.63] | 15.11 [15.08–15.24] |
| After recognition completes | 94.56 [91.00–96.14] | 103.13 [99.41–106.30] |
| Enabled, eight seconds later | 94.38 [77.31–96.02] | 34.78 [23.41–37.89] |
| Disabled again, five seconds later | 82.33 [75.44–95.98] | 34.78 [23.36–37.86] |

These are phase snapshots, not measured peaks. The two recognitions consume a median 1.095 process
CPU seconds [1.042–1.100], excluding earlier startup. Three-second quiet intervals average 0.028%
of one CPU while initially disabled and 0.043% after enabled work settles; these tiny app-process
values include AppKit activity and do not establish an OCR idle-CPU delta. Recognition also uses
Apple-managed compute whose total system/GPU cost is not captured by process CPU time.

Cold disabled startup creates no OCR schema, worker, recognition request or derived-text load.
Disabling cancels work and releases owned query/indexer state, but Apple framework memory remains
after prior recognition. Therefore the literal zero-RAM requirement after use is **not satisfied**
by these measurements. The normal app with all other features active has not been certified against
its full memory budget. Large/complex document peaks also remain unmeasured.

## Recognition quality and bounds

Recognition keeps a 4,194,304-pixel bitmap budget and a maximum 4096-pixel edge. Long images use
sequential 2048-pixel tiles with 256-pixel overlap. This fixes a tall-screenshot failure without
increasing the decoded pixel budget. `minimumTextHeightFraction` is zero because
[Apple's default relative-height cutoff](https://developer.apple.com/documentation/vision/recognizetextrequest/minimumtextheightfraction)
can skip small text in screenshots and pages. Other limits remain 32 MB input files, 64 PDF pages
and 32 KB extracted UTF-8 text. Embedded PDF text is preferred; scanned pages use OCR.

A separate synthetic corpus recognizes every expected line in English multiline text, German text,
a 14-pixel-font screenshot and a 2000×5000 tall screenshot. The Japanese sample misses one character
and changes spacing. Exact outputs are in the JSON record. This small corpus is not a Raycast A/B
comparison, and rotation, noisy scans and broader language coverage remain unvalidated.

## Validation and artifacts

- The isolated PR checkout on upstream `17ed8a1` passes all 64 shipped-source harnesses, including
  new opt-in, persistence, cancellation, retention,
  old-history, pinning, type-saturation and tall-screenshot regressions.
- The isolated PR Debug build passes with only the existing AppIntents metadata warning; lint
  passes with existing warnings, and Model purity passes.
- Spec and standards reviews found lifecycle/cache defects, which were fixed and rechecked.
- Three original working-tree app fixtures verify late-result selection, pin/unpin selection, rapid off/on recovery,
  original type classification and copying through the private board.
- Computer Use verifies that query `7391` displays the image and PDF and that Images Only retains
  the matching image, with its original preview and no OCR loading indicator.

Ignored artifacts under `build/performance/clipboard-ocr-opt-in/` contain the benchmark and app-host
sources, copied synthetic databases, raw timing/CPU JSON, quality samples, sandbox identities and
final test/build/lint logs. The final app runs are `candidate-memory-5`, `candidate-memory-6` and
`candidate-preview-7`. Earlier exploratory runs are retained but excluded from the final aggregates.

## Isolated PR app check

A fresh app-module fixture linked the Debug build of this PR on upstream `17ed8a1`. It used the same
verified sandbox/private-board isolation, two recognition inputs and UI assertions described above.
This single run confirms integration after removing unrelated working-tree changes; it is not a
statistical comparison with upstream. `AppCore.start` and global services remain disabled.

| Phase | RSS, MiB | Physical footprint, MiB |
| --- | ---: | ---: |
| Cold disabled, settled | 59.44 | 14.89 |
| After two recognitions | 86.91 | 106.28 |
| Enabled, eight seconds later | 85.94 | 37.81 |
| Disabled again, five seconds later | 85.89 | 37.75 |
| Palette open | 127.78 | 52.39 |
| Palette closed, settled three seconds | 130.06 | 51.24 |

Recognition used 1.119 process CPU seconds. These phase snapshots are not peak measurements.
The fixture exceeds 100 MB and does not return to its cold baseline, so this contribution does not
establish compliance with the upstream memory bar. There is no matched upstream fixture comparison
to attribute all palette memory to OCR. Selection during late publication, pin/unpin selection,
original type classification, rapid off/on recovery and copying to the private board all pass.
Matched before/after video and a Raycast A/B comparison remain outstanding.

`leaks --atExit` with `MallocStackLogging=1` reported 341 allocations / 21,344 bytes. The root stacks are AppIntents/LinkServices XPC connections (285 allocations) and HIToolbox keyboard-layout XML strings (56 allocations). No OCR owner appears in those root stacks, but this is not a zero-leak result and no matched baseline was run. Instrumented memory is excluded from the uninstrumented memory table.
