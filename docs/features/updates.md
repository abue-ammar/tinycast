# Updates

By default, Tinycast checks GitHub Releases once a day and offers the newest release for its own
channel in a pill in the palette, then installs it at the next relaunch or quit. There is no Sparkle
and no appcast: the release feed the website already reads is the feed the app reads.

## Invariants

- **Tinycast installs its own updates, and Homebrew stays out of the way.** Every cask declares
  `auto_updates true`, which is Homebrew's own flag for an app that manages its own version. `brew
update && brew upgrade` therefore skips Tinycast entirely — it is never reported outdated, never
  re-downloaded, and a self-updated copy is never trashed or rolled back. `brew install`, `brew
uninstall` and `brew list` keep working unchanged.
- **The archive is a zip, never the DMG.** A zip expands with `ditto`; a DMG would have to be mounted,
  which means a volume, a Spotlight handle and a detach that can fail. A release published without a
  zip is not installable and is not offered.
- **The zip is chosen by architecture.** A stable release carries a thin arm64 zip and a
  `-Universal-` one. Intel takes the universal zip and is offered _nothing_ if it is missing, since a
  thin build would install and then refuse to launch; Apple silicon prefers the thin zip and falls
  back to universal.
- **A downloaded update is never quarantined.** macOS sets that flag for sandboxed downloaders and
  for apps that opt in with `LSFileQuarantineEnabled`, and Tinycast is neither. `Quarantine` checks
  anyway, and an app that still carries the flag is refused rather than installed.
- **Two independent trust roots, either of which may change alone.** A downloaded bundle is trusted
  when its seal passes strict validation, nested helpers included, _and_ either its zip carries a
  valid Ed25519 signature from the release key in `TinycastUpdatePublicKey` and the bundle is
  Developer ID signed by any team, or it satisfies the running copy's own designated requirement.
  Nothing is pinned: a new Apple team still updates through the key, and a new key through an
  unchanged identity. Changing both in one release strands everyone. `notarized` is deliberately not
  checked — it resolves the ticket through `syspolicyd` or the network, so an offline Mac would
  refuse a bundle the signature already proves is ours.
- **A build only ever updates within its own channel.** The channels are separate bundle ids installed
  side by side; crossing would mean installing a different app. `com.tinycast.app.dev` never updates
  at all, and does not advertise the command.
- **Nothing is installed unless every check passes.** Bundle id, version and signature are all checked
  on the expanded copy, and the running app survives any failure untouched.
- **The swap waits for quit.** A verified update stays staged until Tinycast quits, by Relaunch or
  any other way, so no old code ever loads a resource or helper from the new bundle.
- **Only the exact bytes verified are installed.** Any process can write to Caches while the update
  waits, so the swap re-runs the trust check and requires the code-directory hash recorded at
  verification. It also skips the swap when the installed app is no longer the version running, so
  a `brew upgrade` made meanwhile is never rolled back.
- **Relaunching goes through `NSApp.terminate`, never `exit`.** That is what flushes a pending note
  draft and hands back the Hyper Key's HID-level caps remap, which outlives the process.
  Relaunch schedules termination through the main run loop, outside any Swift task or dispatch
  callback, so AppKit's nested termination loop can run the main-actor cleanup. The delegate returns
  `terminateLater` and replies when cleanup finishes, preserving system logout and shutdown requests.
  A reopen is scheduled once, only when termination is committed, and waits for the old process to exit.
- **An update never interrupts.** The automatic check only sets `UpdateCoordinator.stage`, and
  `UpdatePill` shows it the next time the palette opens. `announcedVersion` limits an offer to once
  per version per launch. Download and verification need no `UpdateReadiness` check, because nothing
  changes until quit.
- **Only `UpdatePill` reads `stage`.** It stands alone in the footer and the compact header, so a
  download tick never re-renders the palette around it.
- **Automatic checking is optional; manual checking stays available.** Settings → General →
  Automatically check for updates defaults on. Turning it off stops the background task and any
  in-flight automatic request, so neither a response nor a cached release can make a new offer.
  The preference travels through settings backups and `general.automaticallyCheckForUpdates` in
  settings.json; release metadata stays in the feature's own cache file.
- **The app shows no release notes.** The Changelog item in the palette's app menu opens
  `https://tinycast.dev/changelog/`.

## The pill

| Stage              | Shows                                                             | Button   | ×                                           |
| ------------------ | ----------------------------------------------------------------- | -------- | ------------------------------------------- |
| `available`        | the version                                                       | Update   | hides it until the next launch              |
| `installing`       | a ring and percent for the download, then a spinner and the phase | none     | cancels                                     |
| `readyToRelaunch`  | Update ready                                                      | Relaunch | hides it; the update still installs at quit |
| `failed`           | Update failed                                                     | Details  | hides it                                    |
| `idle`, `checking` | nothing                                                           |          |                                             |

A pill cannot hold a failure's text, so Details opens a dialog with the reason and Try Again.

The pill sits beside the menu circle in the footer. The compact bar has no footer, so there it ends
the header row. It cannot reuse `ExtensionToastPill`, because extension views stay in
`Features/Extensions/`, and an extension toast covers it.

## Channel and version

`ReleaseChannel` is derived from the bundle id, and nothing else:

| Bundle id               | Channel        | Takes       |
| ----------------------- | -------------- | ----------- |
| `com.tinycast.app`      | `.stable`      | releases    |
| `com.tinycast.app.beta` | `.beta`        | prereleases |
| anything else           | `.development` | nothing     |

`AppVersion` parses `MAJOR.MINOR.PATCH` and `MAJOR.MINOR.PATCH-beta.N` with semver precedence: a
prerelease sorts below the release it leads to, and `beta.10` above `beta.9`. Everything else parses
to nil, so an off-shape tag can never be offered as an update. A release whose tag disagrees with
its `prerelease` flag is treated as mis-published and skipped.

The Intel build is _not_ a channel. It shares the stable tag, version, bundle id and signature, so it
resolves to `.stable` like any other; `ReleaseArchitecture` picks its asset, and nothing about
identity changes.

## Checking

`UpdateCheckStore` copies `CurrencyRateStore`: a private `.ephemeral`, `urlCache = nil` session, a
self-rescheduling pump, and one atomic JSON file.

```text
~/Library/Caches/<bundle-id>/update-check.json
```

It holds `lastCheckedAt`, the newest release seen, and the version just installed. Freshness is
measured from `lastCheckedAt`, so relaunching never re-asks GitHub; the interval is 24 h, dropping to
2 h after a failed attempt, and the first check waits 30 s so it never lands in the login rush. The
request carries a `User-Agent`, which the GitHub API rejects requests without.

Disabling automatic checks takes effect immediately and survives relaunch. Turning them back on
resumes the same schedule, with the startup delay and cached check time respected. Check for Updates
always works independently of this preference, including while automatic checking is disabled.

**× means later.** On an offered version it hides the pill and records nothing, so the pill comes back
at the next launch, or sooner for a newer release. Check for Updates always offers whatever is newer
than what is running, unless an update is already downloading or waiting for quit. Then it shows that
update instead, since offering it again would discard the download or the staged copy.

Check for Updates reports in a HUD: progress while it asks, then up to date or unreachable. When there
is an update, it opens the palette so the pill shows.

## Installing

One route, whatever the install came from:

1. Stream the zip into `~/Library/Caches/<bundle-id>/Updates/`, with real byte progress and a Cancel
   that actually aborts the transfer, then fetch its `.sig` and check it against the release key.
2. `ditto -x -k` it into a staging folder, and take whatever `.app` lands there — the bundle is named
   for its channel, so it is `Tinycast Beta.app` on beta.
3. Check quarantine natively; clear it if somehow present, and refuse the update if it survives.
4. Verify the bundle id, the version, and that the code signature is valid and proves the bundle is
   ours — through the release key, or through the running copy's own designated requirement — and
   record its code-directory hash. A `.sig` that fails to download is logged and treated as absent.
5. Offer Relaunch. At quit, by Relaunch or otherwise, the staged bundle is checked again against
   that hash, so a copy changed since staging is discarded, and `FileManager.replaceItemAt` swaps
   it in. The staging folder is on the same volume as `/Applications`, which is what lets this be
   atomic. A copy Tinycast cannot write is reported before the download starts, not worked around;
   there is no privileged helper.
6. Relaunch spawns a detached waiter that reopens the app once this process exits — `open` on a
   bundle id that is still running would only re-activate the instance on its way out.

A successful install records its version as `installedVersion`. The first launch running that
version takes it and shows an "Updated to Tinycast <version>" HUD, whether it came from Relaunch or a
later quit and reopen. A launch of an older version shows that the update could not be installed,
since the swap at quit has no window to report in. A newer version only clears it, so a brew or DMG
install never reports.

Nothing here touches `~/Library/Preferences`, `~/Library/Caches` or `Application Support`, so no
setting, clipboard entry, note or snippet is affected by an update, by `brew upgrade`, or by both.

## Releasing into it

`.github/workflows/release.yml` publishes two assets from one build: the DMG people download by hand
and the cask installs, and `Tinycast-<version>.zip` for the updater. A stable run adds a
`Tinycast-Universal-<version>` pair from its `universal` job, uploaded second so the thin zip stays
first in the asset list — builds predating architecture-aware selection take whichever comes first.
The zip is made with

```sh
ditto -c -k --keepParent --sequesterRsrc "$APP" "dist/$ZIP_FILE"
```

which is the only zip that leaves the code signature verifiable — plain `zip` drops symlinks and
breaks the seal, and the signature check above would then reject every update.

The body it publishes is composed by `Scripts/release-notes.sh`: GitHub's generated changelog first,
then `<!-- tinycast:install -->`, then the install text. The app does not read the body. Anything a
release wants the website's changelog to show has to go above that marker — see
[release.md](../release.md#release-notes).

**Every cask must declare `auto_updates true`**, in homebrew/cask and in the tap. Without it Homebrew
compares its Caskroom receipt against the cask version, sees a self-updated app as outdated forever,
and re-installs over it on the next `brew upgrade`.
