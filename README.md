# Tinycast

A tiny, fully native macOS launcher — the essentials, without the bloat.

<p align="center">
  <a href="https://discord.gg/v2Eeb4QQy3">
    <img alt="Join the Tinycast Discord"
         src="https://img.shields.io/badge/Discord-Join%20the%20community-5865F2?style=flat&logo=discord&logoColor=white"></a>
  <a href="mailto:iabueammar@gmail.com?subject=Hiring%20enquiry">
    <img alt="Hire me — iabueammar@gmail.com"
         src="https://img.shields.io/badge/Hire%20me-Let's%20talk-111111?style=flat&logo=gmail&logoColor=white"></a>
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
</p>

<p align="center">
  <img src="docs/screenshot.png" alt="Tinycast command palette" width="720">
</p>

Around **5 MB on disk** and **under 100 MB of RAM** — no Electron, no telemetry, no background
CPU churn. Just SwiftUI + AppKit with zero dependencies. It's fast because there's nothing to it.

It also **runs Raycast extensions** — the real ones, rendered as native SwiftUI. No Node.js, no
browser: JavaScriptCore ships with macOS, so that costs no extra binary size.

## Support

Tinycast is free, and it stays that way. If it earns a place in your daily flow, a one-off tip helps
keep it actively maintained. GitHub Sponsors isn't available in my country, so please support here:

<p align="center">
  <a href="https://buy.polar.sh/polar_cl_NDVFC20DKQpLcNawsh97QzbARBXD3WNn8v35R0mbJmT">
    <img alt="Support Tinycast" width="188" height="44" src="docs/support-button.svg"></a><br>
  <sub>Payments are handled securely by <a href="https://polar.sh">Polar.sh</a>.</sub>
</p>

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).
- **Search Files** — open files and folders from the folders you choose, through Spotlight, with no
  index of our own.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Calculator** — do math, unit, live currency and crypto conversions inline, right in the palette.
- **Quicklinks** — turn a URL, search, file or deeplink into a command, with placeholders for typed
  input, the clipboard or the date.
- **Snippets** — reusable Markdown templates with dynamic placeholders, arguments, nested references
  and optional keyword expansion.
- **Custom commands** — run named shell commands through fuzzy search or their own global hotkeys.
- **Window management** — 34 Rectangle-style actions: halves, quarters, thirds, sizing, nudging,
  display moves, fullscreen and Spaces.
- **System actions** — lock, sleep, restart, empty trash, toggle appearance, Bluetooth, mute, hidden
  files, and more.
- **Calendar and meetings** — your next meeting on the empty palette and in the menu bar, one key to
  join it, or let it join itself.
- **Notes** — an unlimited collection of plain Markdown files in one floating editor, searchable from
  the palette.
- **Emoji picker** — a searchable emoji grid, one keystroke away.
- **AI chat** — bring your own key, chat from the palette. Off out of the box, like every AI feature.
- **Quick Actions** — fix grammar, rewrite, translate or summarize the selected text in any app.
- **Raycast extensions** — run the ones you already have natively, rendered as SwiftUI.
- **Backup and import** — export your settings to a file, or import your setup from Raycast.

## Install

First, add the tap:

```sh
brew trust --tap abue-ammar/tinycast   # required for third-party taps
brew tap abue-ammar/tinycast
```

Then run the one line that matches your Mac:

| Your Mac                         | Install                                  |
| -------------------------------- | ---------------------------------------- |
| Apple silicon, macOS 26 or newer | `brew install --cask tinycast`           |
| Intel, macOS 26                  | `brew install --cask tinycast-universal` |
| macOS 15 Sequoia                 | `brew install --cask tinycast-sequoia`   |

Not sure which you have? **Apple menu → About This Mac.** Homebrew checks too, and refuses the
wrong one.

Want early builds? `brew install --cask tinycast@beta` puts `Tinycast Beta.app` beside the stable
app, with its own settings and permissions. Apple silicon, macOS 26+.

Homebrew clears the macOS quarantine flag on every install and update, so there is nothing else to
run. Downloading a DMG from [Releases](https://github.com/abue-ammar/tinycast/releases) instead?
Tinycast is self-signed, so clear the flag once:
`xattr -dr com.apple.quarantine "/Applications/Tinycast.app"`.

## Permissions

**Accessibility** — needed when Tinycast pastes or expands text into another app, and the only
permission snippet keyword expansion needs. You're prompted when you first use a feature that needs
it; grant access in **System Settings → Privacy & Security → Accessibility**. Snippets ship
disabled, and keystrokes are matched locally, never stored and never sent anywhere.

## Using it

1. Open **Settings → General** and record a global shortcut to summon Tinycast.
2. Press it anywhere → the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → Shortcuts** — search an app or custom command and record a global shortcut.
5. **Settings → Snippets** — enable the feature, then create templates with expansion keywords.

## Building from source

See **[docs/development.md](docs/development.md)** for the toolchain, build, packaging, release and
website workflows. **[docs/](docs/README.md)** indexes everything else — architecture, engineering
standards, the design system and one document per feature.

## Contributing

> [!IMPORTANT]
> **Open an issue before you write code — this is mandatory.** Get the bug or the feature agreed on
> first; discussing it in the issue (or on [Discord](https://discord.gg/v2Eeb4QQy3)) is strongly
> encouraged. A PR with no agreed issue behind it gets closed however good the patch is, and the
> work is wasted. Typo and docs-only fixes are the one exception.

Read **[CONTRIBUTING.md](CONTRIBUTING.md)** first — it covers the memory budget every PR is held to,
the before/after video requirement for visual changes, and why features get declined. Every PR fills
in the **[pull request template](.github/PULL_REQUEST_TEMPLATE.md)**. Security issues go through
[SECURITY.md](SECURITY.md), not the issue tracker.

Questions, ideas, or just want to follow along? **[Join the Discord](https://discord.gg/v2Eeb4QQy3)**.

## License

[AGPL-3.0](LICENSE)
