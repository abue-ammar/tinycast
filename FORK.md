# Tinycast fork — local notes

Fork of [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast) (`origin` = brayd3nmay/tinycast, `upstream` = abue-ammar/tinycast). The installed `/Applications/Tinycast.app` is built **from this repo**, not from the Homebrew cask (uninstalled 2026-09-14). Updates flow through the fork: see "Updates" below.

Upstream's own docs cover the codebase: `docs/architecture.md`, `docs/development.md`, `docs/features/extensions.md`. What follows is only what those don't tell you.

## Why this fork exists

Two extension-runtime bugs, found while debugging the Raycast **downloads-manager** extension (both broke it; both fixed here, neither upstream yet):

1. **`fs.opendirSync` missing** — `Scripts/raycast-runtime/src/node-shims.js` had no `opendirSync`/`opendir`/`promises.opendir`, so any extension iterating a directory with a `Dir` handle threw `TypeError: opendirSync is not a function`. Fixed with a `Dir` class backed by the existing one-shot host `readdir`.
2. **File paste landed on the palette** — in `Tinycast/Features/Extensions/Service/ExtensionHostBridge.swift`, `Clipboard.paste({file})` synthesized ⌘V while Tinycast's palette was still the key window (the palette is a *non-activating* panel: the user's app stays active but the panel holds key focus, so HID-level ⌘V goes to it). The text-paste path handles this; the file path didn't. Fixed by hiding the palette, then `Paster.pasteCurrentContents(into:)` — the 0.35s settle delay there is empirical, from a working JS-side prototype of the same fix.

These may land upstream eventually — check before merging upstream to avoid conflicts, and drop the local diff if upstream fixes them.

## Build & install (the loop actually used here)

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
  -derivedDataPath build build
killall Tinycast; ditto build/Build/Products/Release/Tinycast.app /Applications/Tinycast.app
rm -rf build   # else the build-product copy shows up in Spotlight/Launchpad as a second Tinycast
open -a Tinycast
```

- `DEVELOPER_DIR` is required: `xcode-select` on this machine points at CommandLineTools.
- **Release**, not Debug: Debug builds a separate app (`Tinycast Dev.app`, bundle id `com.tinycast.app.dev`) with its own settings/data/TCC grants. Release is `com.tinycast.app` and picks up all existing user data in `~/Library/Application Support/com.tinycast.app/`.
- Signing uses the **`Tinycast Self-Signed`** identity, already in the login keychain — don't recreate it casually (see `docs/signing.md` for why the stable identity matters). One machine-specific trap: recreating it per those docs needs `openssl pkcs12 -export -legacy`; OpenSSL 3's default format fails macOS `security import`.

## The JS runtime

- Regenerating `RaycastRuntime.generated.js` after shim edits: see `docs/features/extensions.md`. Fork convention: keep the regenerated file in the same commit as the source change.
- Test an extension headlessly without launching the app:
  `node Scripts/raycast-runtime/test.mjs <extension-dir> <command-name>`
  It prints the render tree and the host-call sequence — the host-call *order* is how the paste fix was diagnosed. Point it at an installed extension dir under `~/Library/Application Support/com.tinycast.app/extensions/`.
- Bare `node test.mjs` (fixtures mode) hangs with an "unsettled top-level await" warning — pre-existing upstream, not caused by the local changes. Only the per-extension mode is used here.

## Debugging extensions

- Extensions are prebuilt single-file CJS bundles in `~/Library/Application Support/com.tinycast.app/extensions/<name>/` — plain editable JS, no signature. Prepending a polyfill/wrapper to a command bundle is a fast way to test a runtime fix before touching Swift (that's how both fixes here were proven). Bundles get overwritten when the extension is reinstalled/updated.
- Extension prefs/cache live in `extension-data/<name>.json` next to `extensions/`; its mtime tells you whether a command actually ran.
- There is **no logging**: extension errors don't reach the unified log (`log stream` shows nothing), and errors surface only in the palette UI. The harness above is the observable substitute.
- `raycast://extensions/<author>/<extension>/<command>` deeplinks work (`open "raycast://..."`) — Tinycast claims the `raycast://` scheme. Parsing is in `Tinycast/Features/Extensions/Model/ExtensionDeepLink.swift`.

## Updates

The in-app updater is pointed at **this fork's releases** (`ReleaseFeed.repository = "brayd3nmay/tinycast"`), so the update dialog only ever offers builds that carry the local fixes — "Update Now" is safe to click.

The pipeline, end to end:

1. `.github/workflows/sync-upstream.yml` runs **weekly (Mondays 14:00 UTC)** on the fork: finds upstream's latest stable release, merges its tag into `main` (regenerating the runtime after the merge), pushes, and triggers `release.yml` with the same version number.
2. `release.yml` (upstream's own workflow) builds, signs with the `Tinycast Self-Signed` identity from the fork's `SIGNING_P12_BASE64`/`SIGNING_P12_PASSWORD` secrets — the *same* identity local builds use, so updates keep TCC grants — and publishes a GitHub release on the fork.
3. The installed app sees the new release and shows the update dialog.

Merging and the generated runtime: `.gitattributes` marks `RaycastRuntime.generated.js` with `merge=ours`, so merges keep the local copy and the file is rebuilt from merged sources afterwards — the workflow does this automatically; locally, run `git config merge.ours.driver true` once to get the same behavior, and regenerate after merging. Never hand-merge that file. If upstream conflicts with the local diff in *source* files, the sync run fails — merge the tag locally, resolve, regenerate, push, and re-run the workflow.

Notes:
- Scheduled workflows on forks need Actions enabled once (fork's Actions tab), and GitHub auto-disables cron workflows after ~60 days without repo activity — it emails first; re-enable is one click.
- The fork's signing secrets contain **only** the Tinycast self-signed identity, minted separately — never bulk-export the login keychain per upstream's `docs/signing.md` §2 on this machine; it also holds an unrelated `keyheat-dev` identity.
- `release.yml`'s Homebrew-cask and Discord steps skip gracefully (their secrets aren't set on the fork).

## Gotchas

- macOS version check: the cask required macOS ≥ 26; this machine runs 27. Xcode 26+ needed to build.
- Local builds stamp `CFBundleShortVersionString` as `0.1.0` (release versions are stamped by CI), so after a local rebuild the app will offer the fork's latest release as an "update" — accepting it is harmless (same code, CI-built), or just ignore it.
- Because the signing identity differs from the old Homebrew build, macOS treated the first launch of the forked build as a new app for TCC: Accessibility (and Input Monitoring, if used) needed re-granting once. Future rebuilds keep the grants as long as the `Tinycast Self-Signed` identity is unchanged.
