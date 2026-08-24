# Updates

Tinycast checks GitHub Releases once a day, offers the newest release for its own channel in a native
window with its release notes, installs it and relaunches. There is no Sparkle and no appcast: the
release feed the website already reads is the feed the app reads.

## Invariants

- **Tinycast installs its own updates, and Homebrew stays out of the way.** Both casks declare
  `auto_updates true`, which is Homebrew's own flag for an app that manages its own version. `brew
  update && brew upgrade` therefore skips Tinycast entirely — it is never reported outdated, never
  re-downloaded, and a self-updated copy is never trashed or rolled back. `brew install`, `brew
  uninstall` and `brew list` keep working unchanged.
- **The archive is a zip, never the DMG.** A zip expands with `ditto`; a DMG would have to be mounted,
  which means a volume, a Spotlight handle and a detach that can fail. A release published without a
  zip is not installable and is not offered.
- **Nobody ever runs `xattr`.** An archive Tinycast fetched itself is not quarantined — macOS sets
  that flag for sandboxed downloaders and for apps that opt in with `LSFileQuarantineEnabled`, and
  Tinycast is neither. `Quarantine` checks anyway through `getxattr`/`removexattr` rather than the
  `xattr` tool, and an app that still carries the flag is refused rather than installed.
- **A matching signing identity is the only integrity guarantee.** Tinycast is self-signed and never
  notarized, so a downloaded bundle is trusted when its seal validates *and* its leaf certificate is
  byte-identical to the running app's. That same match is what preserves the Accessibility (TCC)
  grant across the swap, so it is load-bearing twice over.
- **A build only ever updates within its own channel.** The channels are separate bundle ids installed
  side by side; crossing would mean installing a different app. `com.tinycast.app.dev` never updates
  at all, and does not advertise the command.
- **Nothing is installed unless every check passes.** Bundle id, version and signature are all checked
  on the expanded copy before `replaceItemAt` runs, and the running app survives any failure untouched.
- **Relaunching goes through `NSApp.terminate`, never `exit`.** That is what flushes a pending note
  draft and hands back the Hyper Key's HID-level caps remap, which outlives the process.
- **An automatic prompt defers to whatever the user is doing, and is never spent unshown.**
  `UpdateReadiness` withholds it while a snippet is expanding, an extension command is running, an
  uninstall is trashing, a shortcut is being recorded, a prompt or dialog is up, or the palette is
  open. A withheld prompt is still owed: `presentIfAvailable` answers `false`, the version is left
  unannounced, and the pump re-offers it every two minutes for half an hour before falling back to
  the daily rhythm. That is what a hand-launched copy depends on — its one announcement falls 30 s
  in, straight into the palette the user opened the app to use, where a launch-at-login copy would
  have found the desktop idle. The window itself still appears at most once per version per launch:
  `announcedVersion` is set the moment an offer lands, so re-offering can never turn into nagging.
  Readiness is asked again at the click.
- **Nothing about updates is persisted in `AppSettings`.** The feature owns one cache file, so no
  `AppSettingsKey` and no `SettingsBackupCoverage` entry exist for it.
- **The window shows the changelog and nothing else.** CI writes install instructions below
  `<!-- tinycast:install -->`, and `ReleaseNotes.summary` — the single reader of that marker, called
  where the feed is parsed so the cache holds the cut text too — drops them. An app that installs its
  own updates has no use for a Homebrew command, and a body published before the marker existed has
  none, so it comes back whole.
- **The notes are laid out by `ReleaseNotesView`, which is this feature's own.** `AttributedString`
  parses inline styling only; headings and bullets are placed by hand or they arrive as literal `##`
  and `*`. `ExtensionMarkdownView` does the same job and is deliberately not reused — an extension's
  views never leave `Features/Extensions/`.
- **`@handle` and `#304` are linked by the app, never by the release body.** GitHub autolinks both on
  the web, and a bare mention is what notifies the contributor, so the published body keeps them
  plain and `ReleaseNotes` spells them as Markdown links on the way to the window. Both point at
  `ReleaseFeed.repository`, the one place the repo is named.

## Channel and version

`ReleaseChannel` is derived from the bundle id, and nothing else:

| Bundle id | Channel | Takes |
| --- | --- | --- |
| `com.tinycast.app` | `.stable` | releases |
| `com.tinycast.app.beta` | `.beta` | prereleases |
| anything else | `.development` | nothing |

`AppVersion` parses `MAJOR.MINOR.PATCH` and `MAJOR.MINOR.PATCH-beta.N` with semver precedence: a
prerelease sorts below the release it leads to, and `beta.10` above `beta.9`. Everything else parses
to nil, which is deliberate — the repo also publishes `v0.9.7-sequoia` for the macOS 15 cask, and
rejecting the tag is what keeps a beta install from drifting onto the Sequoia build. A release whose
tag disagrees with its `prerelease` flag is treated as mis-published and skipped.

## Checking

`UpdateCheckStore` copies `CurrencyRateStore`: a private `.ephemeral`, `urlCache = nil` session, a
self-rescheduling pump, and one atomic JSON file.

```text
~/Library/Caches/<bundle-id>/update-check.json
```

It holds `lastCheckedAt`, the newest release seen, and the version the user dismissed. Freshness is
measured from `lastCheckedAt`, so relaunching never re-asks GitHub; the interval is 24 h, dropping to
2 h after a failed attempt, and the first check waits 30 s so it never lands in the login rush. The
request carries a `User-Agent`, which the GitHub API rejects requests without.

**Later means skip.** It records the version, so that release stops asking; a newer one still asks.
Check for Updates ignores the record and always offers whatever is newer than what is running.

## Installing

One route, whatever the install came from:

1. Stream the zip into `~/Library/Caches/<bundle-id>/Updates/`, with real byte progress and a Cancel
   that actually aborts the transfer.
2. `ditto -x -k` it into a staging folder, and take whatever `.app` lands there — the bundle is named
   for its channel, so it is `Tinycast Beta.app` on beta.
3. Check quarantine natively; clear it if somehow present, and refuse the update if it survives.
4. Verify the bundle id, the version, and that the code signature is valid and carries the same leaf
   certificate as the running app.
5. `FileManager.replaceItemAt`. The staging folder is on the same volume as `/Applications`, which is
   what lets this be atomic. A non-writable `/Applications` is reported, not worked around; there is
   no privileged helper.
6. Offer Relaunch, which spawns a detached waiter that reopens the app once this process exits —
   `open` on a bundle id that is still running would only re-activate the instance on its way out.

Nothing here touches `~/Library/Preferences`, `~/Library/Caches` or `Application Support`, so no
setting, clipboard entry, note or snippet is affected by an update, by `brew upgrade`, or by both.

## Releasing into it

`.github/workflows/release.yml` publishes two assets from one build: the DMG people download by hand
and the cask installs, and `Tinycast-<version>.zip` for the updater. The zip is made with

```sh
ditto -c -k --keepParent --sequesterRsrc "$APP" "dist/$ZIP_FILE"
```

which is the only zip that leaves the code signature verifiable — plain `zip` drops symlinks and
breaks the seal, and the signature check above would then reject every update.

The body it publishes is composed by `Scripts/release-notes.sh`: GitHub's generated changelog first,
then `<!-- tinycast:install -->`, then the install text. Anything a release wants the update window to
show has to go above that marker — see [release.md](../release.md#release-notes).

**The casks must declare `auto_updates true`** in `abue-ammar/homebrew-tinycast`. Without it Homebrew
compares its Caskroom receipt against the cask version, sees a self-updated app as outdated forever,
and re-installs over it on the next `brew upgrade`.
