# Clipboard OCR reliability and memory follow-up

Addresses the [PR #522 feedback](https://github.com/abue-ammar/tinycast/pull/522#issuecomment-5608070797)
and the resource concerns in [issue #451](https://github.com/abue-ammar/tinycast/issues/451).
The baseline is the initial PR commit `e0e64a3`; unrelated working-tree changes are excluded.

## Behavior changes

- The palette no longer blocks indexing. Recognition still waits for two seconds without system
  input; after that it can finish and publish matches while the clipboard palette remains open.
- A 250 ms pause between items replaces the fixed two-second pause. Active input still defers work;
  only one item is processed at a time.
- Failures are distinct from successful empty recognition. They retry after 30 seconds, up to three
  attempts, while other items can proceed. An empty queue exits; a queue containing only future
  retries sleeps until the next deadline. New captures wake that sleep.
- Enabling OCR resets failed and empty attempts so earlier failures can recover, while retaining
  nonempty recognized text. This also reconsiders empty inputs on a later enabled launch. Persistent
  failures stop retrying within the session; no spinner, skeleton or per-item error popup is added.
- A bundled helper owns Vision/PDF extraction state and exits after each item. The parent accepts
  bounded text through a pipe, terminates/reaps cancelled children, and enforces a 60-second deadline.
  The helper's executable name is independent of beta/stable product-name overrides.

The open-palette fixture is red on the baseline: after enabling OCR with the palette already open,
recognition remains blocked for the ten-second test window. The same fixture is green on the
candidate, recognizing both the image and scanned PDF and passing the selection/filter/copy checks.
This reproduces a code-level failure mode; it does not establish what happened in the maintainer's
unplayed QuickTime recording.

## Matched measurements

2026-09-10; M4 Pro, macOS 26.6.2, Swift 6.3.3. Three fresh verified sandbox app-module fixtures per
variant, alternating baseline/candidate. They link the real Debug AppCore, indexer, coordinator and
palette, use a private clipboard, and verify denial of an external filesystem canary before startup.
`AppCore.start` and global capture/services are not called. Workload: one 1000×300 PNG plus one
scanned PDF page. The same host source is used for both variants and queries the derived SQLite table
to observe completion, without calling version-dependent extraction-queue methods.

The table shows medians in MiB. [The JSON record](clipboard-ocr-reliability.json) includes each run,
minimum/maximum values, source hashes and binary identities. These are parent-process phase snapshots,
not peaks or normal-app memory-budget certification.

| Phase | Baseline RSS / footprint | Candidate RSS / footprint |
| --- | ---: | ---: |
| Cold disabled, settled | 66.44 / 13.17 | 66.20 / 14.45 |
| After two recognitions | 90.50 / 104.56 | 67.11 / 13.52 |
| Enabled, eight seconds later | 90.09 / 36.11 | 63.56 / 13.05 |
| Disabled again, five seconds later | 90.09 / 22.77 | 63.52 / 12.92 |
| Palette open | 129.77 / 38.53 | 105.28 / 31.24 |
| Palette closed, settled three seconds | 119.20 / 36.45 | 107.75 / 28.63 |

After recognition, the candidate returns near its cold footprint before opening the palette. This
supports moving extraction ownership out of the parent; it does not mean all system memory or
palette caches are reclaimed. Memory after palette use remains above the cold baseline.

Recognition CPU includes both the parent and reaped children: baseline median 0.700 seconds
[0.688–1.045], candidate 0.782 seconds [0.779–1.014]. The median rises about 12%; ranges overlap in
this small sample. One helper per item repeats process/framework startup. Apple-managed system/GPU
work is not included, and large-document throughput remains unmeasured.

A separate diagnostic samples parent plus child RSS approximately every 50 ms. Its largest observed
combined sample is **126.06 MiB**, including 61.61 MiB parent and 64.45 MiB child. It observes two
children and no surviving child after completion. Sampling can miss shorter peaks; Apple-managed
services are excluded. This run is excluded from the uninstrumented medians above. Moving recognition
into a helper solves its retained parent allocations; it does **not** satisfy a combined 100 MB peak
limit or make the recognition workload free.

## Validation

The shipped-source tests cover retry backoff, recovery after reenabling, exhausted retries, deletion,
fresh capture during a retry sleep, real helper OCR, nonzero exits, cancellation, deadline termination,
reaped child processes and oversized output. Existing search, type, pin and lifecycle tests remain.
All 65 shipped-source harnesses pass. Debug and Release builds pass; the Release build uses the
beta product-name override and verifies that the fixed-name helper is embedded and signed. Lint
passes with existing warnings; Model purity and whitespace checks pass.

Matched `leaks --atExit` runs report 342 allocations / 21,312 bytes for the baseline and 265 /
16,976 bytes for the candidate. Root stacks are AppIntents/LinkServices XPC and HIToolbox keyboard
layout parsing in both runs. No new OCR/worker root appears in those reports, but neither run is
zero-leak. Instrumented runs are excluded from the CPU and memory comparisons.

Raycast quality parity, noisy/rotated multilingual inputs, a full normal-app memory budget and
matched before/after video remain outstanding. Recognition accuracy and bitmap/page/text limits are
unchanged. Global allocator purges or undocumented framework teardown were not introduced.

Ignored diagnostic artifacts and sandbox identities are under `build/pr-diagnosis/` in the isolated
PR checkout. Matched runs are `baseline-memory-2..4` and `candidate-memory-2..4`; the open-palette
regression uses run 2, and `combined-peak.json` records the separate child-process sampling.
