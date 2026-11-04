---
title: Install
description: Homebrew, release channels, direct downloads, and updates.
---

Tinycast needs **macOS 26 or later**, on Apple silicon or Intel.

## Homebrew

Homebrew is the easiest way to install Tinycast.

```bash
brew trust --tap abue-ammar/tinycast
brew install --cask abue-ammar/tinycast/tinycast
```

You only run `brew trust` once. Homebrew won't install from a third-party tap until you trust it.

### Intel Macs

macOS 26 Tahoe is the last release that runs on Intel, so the stable build comes in two versions. The
command above installs a smaller build for Apple silicon only. On an Intel Mac, install the universal
cask instead:

```bash
brew install --cask abue-ammar/tinycast/tinycast-universal
```

If you pick the wrong one, Homebrew stops you: `tinycast` won't install on an Intel Mac. Both casks
give you the same `Tinycast.app`. The universal build also runs on Apple silicon; it's just a larger
download.

### Channels

Each channel is a **separate app** with its own settings, permissions and login item. They can run
side by side, so you can keep the stable version and try a beta at the same time.

| Channel | Cask                 | App                 |
| ------- | -------------------- | ------------------- |
| Stable  | `tinycast`           | `Tinycast.app`      |
| Stable  | `tinycast-universal` | `Tinycast.app`      |
| Beta    | `tinycast@beta`      | `Tinycast Beta.app` |

```bash
brew install --cask abue-ammar/tinycast/tinycast@beta
```

The beta doesn't share settings with the stable version. To move your setup over, use
[Backup](/docs/reference/backup). The two stable casks install the _same_ app, so only one of them
can be installed at a time.

## Downloading directly

Builds are also on the [Releases page](https://github.com/abue-ammar/tinycast/releases).

Open the DMG and drag Tinycast to Applications. Every release is signed with Tinycast's Apple
Developer ID and notarized by Apple, so macOS opens it without a warning.

## Updating

Tinycast updates itself. Once a day it checks for a new release on its own channel. When there is
one, a window shows what changed. **Update Now** downloads and installs it, and **Relaunch** starts
the new version. You can also check at any time with **Check for Updates** in the launcher, the menu
bar or **Settings → About**.

To stop the daily check, turn off **Automatically check for updates** in **Settings → General**.
Checking by hand still works.

Because the app manages its own updates, `brew upgrade` skips Tinycast. This is expected. See
[Updates](/docs/reference/updates) for details.

Every release is signed with the same certificate, so your Accessibility permission keeps working
after an update.

## Uninstalling

```bash
brew uninstall --cask abue-ammar/tinycast/tinycast
```

To remove the files Tinycast created, delete its Application Support and Caches folders, and its
settings:

```bash
rm -rf ~/Library/Application\ Support/com.tinycast.app
rm -rf ~/Library/Caches/com.tinycast.app
defaults delete com.tinycast.app
```

The Application Support folder holds your snippets, notes, quicklinks, clipboard history and AI
chats, so copy out anything you want to keep first. The beta uses `com.tinycast.app.beta` instead.

API keys you saved for AI providers or MCP servers, and extension sign-ins, are stored in your login
Keychain. Remove them in Keychain Access if you want them gone too.

To remove a _different_ app and the files it left behind, use Tinycast's
[built-in uninstaller](/docs/launcher/uninstall).
