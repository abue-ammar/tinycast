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

<!-- Screenshot placeholder — drop the real image at docs/screenshot.png -->
<p align="center">
  <img src="docs/screenshot.png" alt="Tinycast command palette" width="720">
</p>

Around **7 MB on disk** and **under 100 MB of RAM** — no Electron, no telemetry, no background
CPU churn. Just SwiftUI + AppKit, with [Sparkle](https://sparkle-project.org) for updates as the one
dependency. It's fast because there's nothing to it.

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Custom commands** — run named shell commands through fuzzy search or their own global hotkeys.
- **Calculator** — do math, unit and live currency conversions inline, right in the palette.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Snippets** — reusable Markdown templates with dynamic placeholders, arguments, nested references
  and optional keyword expansion.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).

## Install

```sh
brew trust --tap abue-ammar/tinycast   # required for third-party taps
brew tap abue-ammar/tinycast
brew install --cask tinycast          # stable
brew install --cask tinycast@beta     # beta  (installs side-by-side)
```

Each channel is a separate app (`Tinycast.app`, `Tinycast Beta.app`) with its own settings and
permissions, so you can run stable next to the beta.

Tinycast is self-signed. Installing via Homebrew clears the macOS quarantine flag for you
automatically on every install and update, so there's nothing to run. (If you download the DMG
directly from Releases instead, clear it once: `xattr -dr com.apple.quarantine
"/Applications/Tinycast.app"`.)

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

See **[docs/development.md](docs/development.md)** for the toolchain, build, packaging, release,
and website workflows, and **[docs/ui.md](docs/ui.md)** for the UI design system.

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

## Contributors

Thank you to everyone who has put time into Tinycast — every fix and idea shows up in something
people use every day.

<p align="center">
  <a href="https://github.com/abue-ammar/tinycast/graphs/contributors">
    <img alt="Tinycast contributors"
         src="https://contrib.rocks/image?repo=abue-ammar/tinycast&max=28&columns=28">
  </a>
</p>

## License

[AGPL-3.0](LICENSE)
