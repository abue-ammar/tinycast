# Release

How a build reaches a user. The local development loop is in [development.md](development.md);
the signing identity itself is in [signing.md](signing.md).

## Packaging a DMG locally

```sh
./Scripts/build-dmg.sh               # -> build/Tinycast-<version>.dmg (universal: Apple Silicon + Intel)
./Scripts/build-dmg.sh 0.5.7         # -> build/Tinycast-0.5.7.dmg
./Scripts/build-dmg.sh 0.5.7 x86_64  # -> build/Tinycast-0.5.7-x86_64.dmg (Intel-only)
./Scripts/build-dmg.sh 0.5.7 arm64   # -> build/Tinycast-0.5.7-arm64.dmg (Apple Silicon-only)
```

It builds a Release `Tinycast.app` signed with `Tinycast Self-Signed` and packs it with an
`/Applications` symlink. The default is a universal binary; pass `arm64` or `x86_64` as the second
argument to ship a single-architecture DMG. Official per-channel releases are built by CI, below.

## Signing & Gatekeeper

Both local builds and CI releases sign with the same stable `Tinycast Self-Signed` identity, not an
Apple Developer ID — so macOS quarantines a directly-downloaded DMG. The Homebrew cask strips that
automatically; direct downloaders run `xattr -dr com.apple.quarantine "…/Tinycast.app"` once. Full
details in [signing.md](signing.md).

## Continuous integration

`.github/workflows/ci.yml` runs on every PR, on a `macos-26` runner with Xcode 26 (the same selection
step as the release workflow). One job, a merge gate; a new push cancels the in-flight run for the
same ref. Two steps, both of which shell out to a script rather than naming rules or harnesses in the
workflow, so neither can drift:

- **the harnesses** — `./Scripts/run-tests.sh`.
- **lint** — `./Scripts/lint.sh`, with `SWIFTLINT_REPORTER=github-actions-logging` so every violation
  is annotated **inline on the PR diff** instead of being buried in the log. It runs under
  `if: always()`, so a failing harness still surfaces the lint annotations in the same run. Warnings
  annotate only; **lint errors fail the job**, exactly as a local run does.

It does **not** run on pushes to `main`. `pull_request` builds the merge result, so re-running after a
merge would re-test content CI has already seen. A direct push to `main` therefore gets no run at all —
use **Actions → CI → Run workflow** if one ever needs checking.

There is **no `xcodebuild` step**: a Debug build costs minutes on every run and the release workflow
builds before it ships anyway, so CI keeps to the checks that finish in about a minute. The
consequence is that a change compiling nowhere still turns the PR green — **build locally before you
open one**. See [testing.md](testing.md#definition-of-done).

## Releasing

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions, no local machine
needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `beta` or `stable`. Each builds a distinct app (`Tinycast Beta.app` / `Tinycast.app`)
  with its own bundle id, alongside the local `Tinycast Dev.app`. Beta gets an auto-incrementing
  `-beta.N` suffix (`N` = the Actions run number) so re-running never collides; stable ships the
  version as-is.
- **version** — base semver, e.g. `0.2.0`.

It builds on a `macos-26` runner with Xcode 26 and publishes a GitHub Release tagged
`v<full-version>` with a versioned DMG asset (`Tinycast-<full-version>.dmg`), marked prerelease for
beta. On success it also bumps the matching cask in the tap.

### Homebrew tap automation

The release job's final step rewrites the `version` + `sha256` of the channel's cask (`tinycast` or
`tinycast@beta`) in the [`homebrew-tinycast`](https://github.com/abue-ammar/homebrew-tinycast) tap and
pushes. It needs a `HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT with **Contents: read/write**
on the tap repo. Without the secret the step logs a warning and skips; the release still publishes.

## Website

`.github/workflows/website.yml` builds `website/` (Vite + React + TS) and deploys it to GitHub Pages at
`https://abue-ammar.github.io/tinycast/` on every push to `main` that touches `website/`. Enable it
once via **Settings → Pages → Source = GitHub Actions**.

```sh
cd website && npm install && npm run dev     # local preview
```
