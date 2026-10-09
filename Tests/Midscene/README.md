# Tinycast native E2E

This package uses the native `@midscene/test` YAML runner and `@midscene/computer` desktop agent. User operations are `aiAct` and visible outcomes are `aiAssert`; custom `app.open` only prepares and tears down the test world.

Every case must include `aiAct` and end with `aiAssert` checking the final visible
result. Intermediate outcomes should also use `aiAssert`. Model-free collection
rejects missing assertions and actions left after the last assertion, including on PRs.

The design borrows per-case isolation, trusted model execution, shard artifacts and native report
handling from [Rome #466](https://github.com/rome-os/rome/pull/466) and
[its follow-up #551](https://github.com/rome-os/rome/pull/551). Report publication follows
[Rome #678](https://github.com/rome-os/rome/pull/678) at `1fe1e81231744f135f49f6b00dfb7c20240a1e4a`. Tinycast has a native floating
palette, so its application journeys use the computer agent rather than a browser context.

The first cases cover arithmetic, offline unit conversion, and searching/opening a synthetic native application named E2E Lantern. They do not use an installed application, real clipboard history, external websites, or the user's Tinycast data.

Each case copies the Debug application into its own temporary directory, assigns a unique `com.tinycast.app.midscene.*` bundle identifier, and prepares a private defaults domain, Application Support directory, cache and launcher search scope. Its onboarding marker and feature defaults are fixture setup. The Debug-only launch seam requires both that bundle prefix and `TINYCAST_E2E_VISIBLE=1`; it opens the real palette and disables background network fetches and global hotkey registration. Release behavior is unchanged. Teardown terminates only the launched Tinycast PID and fixture applications matching both the exact case bundle and bundle URL.

## Checks without a model

```sh
cd Tests/Midscene
npm ci --registry=https://registry.npmjs.org
npm run check
```

This checks TypeScript, collects the YAML with the real Midscene runner, validates the case manifest and registered AI nodes, and runs native report publication tests. It never opens an application or requires model credentials. Existing Swift business harnesses remain separate.

## Visual execution

Use a dedicated macOS 26 desktop with Accessibility, Screen Recording and System Events automation available. Do not run on a shared personal desktop: the computer agent operates the global display, keyboard and mouse even though application data is private. No model tests run automatically on PRs.

Build the Debug scheme and provide `TINYCAST_APP_PATH` pointing to `Tinycast Dev.app`. Populate the four `MIDSCENE_MODEL_*` keys shown in `.env.example` through your CI secret store or process environment. The runner does not source configuration files; credentials are never passed to Tinycast or its fixture application. Opt in with `MIDSCENE_DESKTOP_ENABLED=1` and run `npm test`. `MIDSCENE_SHARD=calculator` or `launcher` selects one shard. Midscene itself owns lifecycle, timeout, progress and case status.

The GitHub workflow first verifies the `macos-26-intel` desktop and runs model-free validation for PRs. Model secrets are granted only to the visual step on upstream `abue-ammar/tinycast` main, or an explicit manual dispatch in a fork. Set `MIDSCENE_DESKTOP_ENABLED=true` to opt in. Fork pushes and every PR remain secret-free. Recovery dispatches with `report_source_run_id` skip application builds, desktop checks and all model execution.

Report aggregation and artifacts work independently of Pages. Fork publication additionally requires `MIDSCENE_PUBLISH_REPO` to equal the full repository name and a dispatch with `publish_pages=true`. Pages must already use GitHub Actions; CI reads its configuration with `enablement: false` and never enables Pages or changes repository settings. Configure `MIDSCENE_PAGES_PRESERVE_REF` to the repository's static site branch, such as `gh-pages`, to preserve its root website. Reports live under `/midscene/runs/<run>/<attempt>/`; verified deployment URLs, rather than speculative pre-publication URLs, appear in the final Summary.

## Reports

`midscene_run/framework/` contains the native Midscene Test report; every started AI case also exports its native SDK HTML with inline screenshots, final PNG, and runtime metadata recording its isolated PID and bundle. Artifacts are retained on failure for 14 days. A new run removes stale local output before execution. Report merging uses Midscene's native HTML merger; if it fails, the available original reports are preserved and linked, and CI remains failed. Combined publication does not hide missing or failed cases.

The final published Summary uses the Rome layout: attention and passed counts, recorded model names, native report and artifact links, followed by failed, missing and not-run cases. Passed cases appear in a collapsed appendix. A shard-results table precedes the case tables, which show shard, case, an explicit Report link, a 160px screenshot, status/reason and duration. Case names and screenshots link to the recorded step in the native Test report when available; standalone HTML exports remain the fallback.

`available-results` displays only counts, status, failure reasons and artifact links; visual shards do not write separate case Summaries. This saved aggregation result does not depend on Pages jobs, tokens or environment approval. `report-results` reads available reports after publication and shows aggregation and deployment status; it does not remerge or delete native HTML. With Pages disabled or unavailable, counts, failure reasons and downloadable artifacts remain usable. Missing or failed cases never become passes because publication succeeds.

To rebuild a report without calling a model:

```sh
gh workflow run midscene.yml --ref test/midscene-e2e \
  -f report_source_run_id=COMPLETED_RUN_ID -f publish_pages=false
```

Source runs must be completed runs of this workflow in the same repository, including the same head repository. Upstream sources require a main commit with verified ancestry and a trusted push/schedule/manual event. Fork sources require a manual dispatch; legacy fork push artifacts and PR artifacts are intentionally rejected. Artifact download follows successful authentication and uses the source's actual attempt. History lookup applies the same policy and paginates both workflow runs and artifacts, selecting the latest retained attempt.

All three AI journeys passed on GitHub-hosted `macos-26-intel` in
[run 36682718562](https://github.com/quanru/tinycast/actions/runs/36682718562).
Screenshots show the expression result `60`, conversion result `25.4 cm`, and the opened
E2E Lantern window; runtime metadata confirms separate process and bundle identities.
That run also exposed report-copy ambiguity and timing races in two existing Swift harnesses;
the harnesses now wait for explicit completion and port release, and the merger selects only
canonical exports. Model success is initial integration evidence.

The Intel application is cross-built once on an Apple Silicon runner and shared as a zipped
build artifact; each Intel visual shard still runs on a fresh VM. Swift harnesses run on
Apple Silicon. The merger prefers complete native Test reports, falling back to canonical inline
HTML exports and excluding automatic SDK `report/` copies. Without result metadata, available exports remain
linked and mergeable while the case remains missing.

Pages preserves the configured root site and trusted report history for up to three recent runs
within a 900 MiB site limit. Original report artifacts remain available for 14 days; prepared Pages
artifacts retain history for 90 days. Shard, combined and Pages artifact names include the attempt,
and reruns clear prior output before merging so stale evidence is not mixed into new results.

Startup checks the owned application window and focused PID before attempting to raise it. An already ready palette incurs no activation or AppleScript call. Otherwise the owned app is activated natively before attempting AppleScript as a fallback. Startup artifacts record final `ready` and `inspection` separately from historical `attempts` and `warnings`.

The launcher journey uses a synthetic, isolated AppKit fixture. The visible fixture label does not prove its launch origin; the keyboard action trace and owned fixture PID provide that evidence. This case does not cover the global hotkey, the real application index, or a Release distribution package.
