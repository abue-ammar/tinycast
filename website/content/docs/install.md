---
title: Install
description: Homebrew, the release channels, and the one manual step a direct download needs.
---

Tinycast needs **macOS 26 or later**, on Apple silicon or Intel. There is a separate cask for macOS
15 Sequoia — see [Older macOS](#older-macos).

## Homebrew

This is the recommended route, because Homebrew clears the macOS quarantine flag for you on every
install and update.

```bash
brew trust --tap abue-ammar/tinycast
brew install --cask abue-ammar/tinycast/tinycast
```

`brew trust` is required once for any third-party tap; Homebrew refuses to install from an untrusted
tap without it.

### Intel Macs

macOS 26 Tahoe is the last release that boots on Intel, so stable ships twice from the same build.
The command above installs a lean Apple-silicon-only build; on an Intel Mac, install the universal
cask instead:

```bash
brew install --cask abue-ammar/tinycast/tinycast-universal
```

You do not have to work out which you need — `tinycast` refuses to install on Intel, and both casks
give you the same `Tinycast.app`. The universal build runs on Apple silicon too; it is simply the
larger download.

### Channels

Each channel is a **separate application** with its own bundle identifier, settings, permissions and
login item. They run side by side, so you can keep stable installed while trying a beta.

| Channel | Cask                 | App                 |
| ------- | -------------------- | ------------------- |
| Stable  | `tinycast`           | `Tinycast.app`      |
| Stable  | `tinycast-universal` | `Tinycast.app`      |
| Beta    | `tinycast@beta`      | `Tinycast Beta.app` |

```bash
brew install --cask abue-ammar/tinycast/tinycast@beta
```

Because the channels are separate apps, installing the beta does not upgrade your stable install and
does not share its settings. To move settings across, use
[Backup](/docs/reference/backup). The two stable casks are the *same* app, so they cannot be
installed at once — Homebrew picks the right one for your Mac.

### Older macOS

Tinycast also runs on macOS 15 Sequoia through its own cask:

```bash
brew install --cask abue-ammar/tinycast/tinycast-sequoia
```

macOS 26 is the primary target and gets features first.

## Downloading the DMG

Builds are also published on the
[Releases page](https://github.com/abue-ammar/tinycast/releases).

Tinycast is **self-signed** — there is no paid Developer ID certificate behind it — so macOS
quarantines a hand-downloaded copy and refuses to open it. Clear the flag once, after dragging the
app to Applications:

```bash
xattr -dr com.apple.quarantine "/Applications/Tinycast.app"
```

You do **not** need this if you installed through Homebrew.

## Updating

```bash
brew upgrade --cask abue-ammar/tinycast/tinycast
```

Every release is signed with the same certificate, which is what keeps your Accessibility grant
alive across updates instead of asking for it again.

## Uninstalling

```bash
brew uninstall --cask abue-ammar/tinycast/tinycast
```

To remove the files Tinycast created, delete its Application Support and Caches folders:

```bash
rm -rf ~/Library/Application\ Support/com.tinycast.app
rm -rf ~/Library/Caches/com.tinycast.app
```

Your snippets, notes and quicklinks live in that Application Support folder, so copy anything you
want to keep out first.

To remove a _different_ app and everything it left behind, Tinycast has a
[built-in uninstaller](/docs/launcher/uninstall).
