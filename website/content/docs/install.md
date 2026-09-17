---
title: Install
description: Homebrew, the release channels, updates, and the one manual step a direct download needs.
---

Tinycast needs **macOS 26 or later**, on Apple silicon or Intel.

## Homebrew

This is the easiest route. Homebrew clears the macOS quarantine flag for you, so the app opens
without a warning.

```bash
brew trust --tap abue-ammar/tinycast
brew install --cask abue-ammar/tinycast/tinycast
```

You run `brew trust` once. Homebrew will not install from a third-party tap until you trust it.

### Intel Macs

macOS 26 Tahoe is the last release that runs on Intel, so the stable build ships in two sizes. The
command above installs a smaller build for Apple silicon only. On an Intel Mac, install the universal
cask instead:

```bash
brew install --cask abue-ammar/tinycast/tinycast-universal
```

You do not need to work out which one you need. `tinycast` refuses to install on Intel, and both
casks give you the same `Tinycast.app`. The universal build also runs on Apple silicon; it is just a
bigger download.

### Channels

Each channel is a **separate app** with its own settings, permissions and login item. They run side
by side, so you can keep stable and try a beta at the same time.

| Channel | Cask                 | App                 |
| ------- | -------------------- | ------------------- |
| Stable  | `tinycast`           | `Tinycast.app`      |
| Stable  | `tinycast-universal` | `Tinycast.app`      |
| Beta    | `tinycast@beta`      | `Tinycast Beta.app` |

```bash
brew install --cask abue-ammar/tinycast/tinycast@beta
```

The beta does not share settings with stable. To move your setup across, use
[Backup](/docs/reference/backup). The two stable casks are the _same_ app, so you can only have one
of them installed.

## Downloading directly

Builds are also on the [Releases page](https://github.com/abue-ammar/tinycast/releases).

Tinycast is **self-signed**. There is no paid Apple Developer ID behind it yet, so macOS quarantines
a copy you download by hand and will not open it. After you drag the app to Applications, clear the
flag once:

```bash
xattr -dr com.apple.quarantine "/Applications/Tinycast.app"
```

You do **not** need this if you installed with Homebrew.

## Updating

**Tinycast updates itself.** Once a day it checks for a new release on its own channel. When one is
out, a window shows what changed, and one click downloads it, installs it and relaunches. You can
also check any time with **Check for Updates** in the launcher, the menu bar or **Settings → About**.

Because the app manages its own version, `brew upgrade` skips Tinycast on purpose. That is expected,
not a bug. See [Updates](/docs/reference/updates) for the details.

Every release is signed with the same certificate, which is what keeps your Accessibility grant
working across updates.

## Uninstalling

```bash
brew uninstall --cask abue-ammar/tinycast/tinycast
```

To remove the files Tinycast made, delete its Application Support and Caches folders:

```bash
rm -rf ~/Library/Application\ Support/com.tinycast.app
rm -rf ~/Library/Caches/com.tinycast.app
```

That Application Support folder holds your snippets, notes, quicklinks, clipboard history and AI
chats, so copy out anything you want to keep first. The beta uses `com.tinycast.app.beta` instead.

API keys you saved for AI or MCP servers, and extension sign-ins, live in your login Keychain. Remove
them in Keychain Access if you want them gone too.

To remove a _different_ app and everything it left behind, Tinycast has a
[built-in uninstaller](/docs/launcher/uninstall).
