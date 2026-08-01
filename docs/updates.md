# Updates

Tinycast updates itself with [Sparkle](https://sparkle-project.org) 2.9.4, pulled in as an SPM binary
target. The `.dmg` the release workflow already publishes *is* the update archive — Sparkle unarchives
`.dmg` natively — so there is no second artifact to build, sign or keep in sync.

Every dialog belongs to Tinycast. `UpdateUserDriver` implements `SPUUserDriver` in full, so Sparkle's
own AppKit windows never appear; a confirmation goes through `AppCore.askConfirmation` and a report
through `AppCore.showNotice`, exactly like the rest of the app (see [ui.md](ui.md#modals--hud)).
Progress is not a dialog at all: the app is an accessory, so a background check that found something
must not steal focus. `AppCore` owns the store as `updates`; `UpdateStore` is `@MainActor` and
publishes one `State` (`idle` / `checking` / `downloading` / `extracting` / `readyToRelaunch` /
`failed`) that the Settings row renders, and nothing appears on screen until there is a question to
ask.

Sparkle 2.9.4 is a floor, not a preference: 2.9.3 opened the update window behind every other window
for dockless apps, which for an `LSUIElement` app means the update UI is simply invisible.

## Why this works for a self-signed app

Tinycast is signed with a stable self-signed identity and is not notarized (see
[signing.md](signing.md)). That would break most update mechanisms, and does not break this one,
because Sparkle never consults Gatekeeper.

`SUCodeSigningVerifier` lifts the **old** bundle's code-signing *designated requirement* —
`identifier "…" and certificate leaf = H"…"` — and checks the downloaded bundle against it. That is a
leaf-certificate hash match against the app that is already installed, not a trust decision about a
certificate chain, so a self-signed identity satisfies it as long as it stays the same identity.
`spctl` is never invoked.

`SUUpdateValidator` accepts an update when **either** the EdDSA signature validates **or** the code
signature matches. Both hold here, which is why either the `.p12` or the EdDSA key alone can keep the
channel alive — and why losing both is unrecoverable. Sparkle refuses the *removal* of a code-signing
identity, so a future build must never ship unsigned.

Quarantine is handled inside Sparkle: `SUPlainInstaller` strips `com.apple.quarantine` from the
installed bundle, so an in-app update needs none of the manual `xattr` step a directly-downloaded DMG
does.

macOS App Management (TCC) does not engage. That protection keys off the Team ID of the app being
modified; Tinycast's bundle carries none, so there is nothing to protect and no "wants to manage
apps" prompt. Nor is there an admin prompt when the app is user-owned in `/Applications`, which is
what a Homebrew install produces.

## Two feeds, not one channel

Each channel gets its own appcast. `sparkle:channel` is the wrong tool here, and not by a small
margin: Sparkle's *default* channel is always allowed, so a beta host subscribed to a beta channel is
still offered the stable DMG. That DMG contains `Tinycast.app` with bundle id `com.tinycast.app`,
which matches neither the beta host's filename nor its bundle id, and the install fails with "No
suitable install is found". Separate feeds make the mismatch impossible rather than merely unlikely.

| bundle id | app | feed |
| --- | --- | --- |
| `com.tinycast.app` | `Tinycast.app` | `https://abue-ammar.github.io/tinycast/appcast.xml` |
| `com.tinycast.app.beta` | `Tinycast Beta.app` | `https://abue-ammar.github.io/tinycast/appcast-beta.xml` |
| `com.tinycast.app.dev` | `Tinycast Dev.app` | none — updates disabled entirely |

`SUFeedURL` is deliberately **absent** from `Info.plist`. The feed is supplied at runtime by
`SPUUpdaterDelegate.feedURLStringForUpdater:`, which wins over `Info.plist`, and which returns `nil`
for any bundle id it does not recognise. That is what makes the dev channel provably un-updatable
instead of merely unconfigured: there is no URL to fall back to. `UpdateStore.isSupported` is false
there, and every update affordance hides.

Both appcasts live in `website/public/` and are served by GitHub Pages. Vite's `base: "/tinycast/"`
copies `public/` to the site root, so `website/public/appcast.xml` becomes
`https://abue-ammar.github.io/tinycast/appcast.xml`.

## Consent

Update checking is a networked feature, so it ships off and is consent-gated like every other one.

`SUEnableAutomaticChecks = NO` in `Info.plist` is what makes "off" mean off: with it, `startUpdater()`
performs **zero** network I/O — `scheduleNextUpdateCheckFiringImmediately:` early-returns before
arming a timer — and the same value permanently suppresses Sparkle's own update-permission prompt, so
the only thing that ever asks is Tinycast's consent sheet. That sheet names the provider (GitHub
Pages), the cadence (daily) and what leaves the machine: an HTTPS GET of a static XML file, and
nothing about the machine, which is what `SUEnableSystemProfiling = NO` guarantees.

`SUHost` prefers the **user default** over `Info.plist`, so writing the `SUEnableAutomaticChecks` user
default at runtime turns background checks on live — no relaunch, and no second flag to keep in sync
with Sparkle's own idea of the setting. Sparkle's default *is* the setting; `UpdateStore.isEnabled`
only republishes it.

That flag deliberately does not live in `AppSettings`: `SettingsBackup` mirrors that type
field-for-field, and importing a backup must not be able to grant network access. Opting out leaves
nothing behind — Sparkle's activity defaults (`SULastCheckTime`, `SUSkippedVersion`) are cleared and
its cache directory under `~/Library/Caches/<bundle-id>/` is deleted.

A user-initiated check is a separate path and always allowed; it is the explicit gesture, so it may
present a dialog immediately. A background check must never steal focus — the app is an accessory,
and an update found while the user is working somewhere else is not an emergency.

## Homebrew coexistence

The cask **must** declare `auto_updates true`. Since Homebrew 6.0.0 that no longer means "brew never
touches this app". `brew upgrade` reads the **installed** app's `Info.plist` and upgrades only when
the installed bundle looks older than the cask's version, so a Tinycast that already updated itself is
never downgraded, while a user who never opens the app is still pulled forward by `brew upgrade`. The
two mechanisms compose instead of fighting.

One constraint follows from that comparison: `CFBundleVersion` must never be `"0"` or `"0.0"`.
Homebrew treats those as unset and silently disables the version comparison, which puts the cask back
to clobbering a self-updated install.

This is a one-line change in each cask, and it lives in the separate
[`homebrew-tinycast`](https://github.com/abue-ammar/homebrew-tinycast) tap — `Casks/tinycast.rb` and
`Casks/tinycast@beta.rb`. The release workflow rewrites only `version` and `sha256`, so adding
`auto_updates true` is a **required manual maintainer step**, not something CI will do for you.

## Two rules with teeth

**Never add an `NSUpdateSecurityPolicy` dict to `Info.plist`.** It forces Sparkle off its atomic-swap
installation path, and the fallback path is exactly the one that reintroduces the "wants to manage
apps" prompt (Sparkle issue #2591). The key looks like hardening and is a regression here.

**Never ship an unsigned build.** Sparkle refuses the removal of a code-signing identity, so the
first unsigned release would not merely be unverifiable — it would strand every install that is
already out there, with no in-app path forward.

## Release mechanics

The release workflow runs Sparkle's `generate_appcast` over the finished DMG, which both EdDSA-signs
it (the key comes from the `SPARKLE_ED_PRIVATE_KEY` secret on stdin, so it never touches a keychain
or a file) and rewrites the channel's appcast — `website/public/appcast.xml` for
stable, `website/public/appcast-beta.xml` for beta — with the new `<item>`, then commits it. That
commit touches `website/`, which is what `.github/workflows/website.yml` triggers on, so the appcast
reaches GitHub Pages through the existing site deploy rather than a second publishing mechanism. Full
pipeline in [development.md](development.md#ci-releases).

## No standalone harness

This subsystem has none, deliberately. Sparkle is a binary framework and both `UpdateStore` and
`UpdateUserDriver` are AppKit- and Sparkle-bound, so there is nothing a Foundation-only `Tools/`
harness could compile — unlike the pure engines listed in [development.md](development.md#tests).
