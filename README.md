# Tinycast

A tiny, fully native macOS launcher — the essentials, without the bloat.

<!-- Screenshot placeholder — drop the real image at docs/screenshot.png -->
<p align="center">
  <img src="docs/screenshot.png" alt="Tinycast command palette" width="720">
</p>

Around **3 MB on disk** and **under 100 MB of RAM** — no Electron, no telemetry, no background
CPU churn. Just SwiftUI + AppKit with zero dependencies. It's fast because there's nothing to it.

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Calculator** — do math, unit and live currency conversions inline, right in the palette.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
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

**Accessibility** — needed only so Tinycast can paste a clipboard item back into the app you
came from. You're prompted the first time you paste; grant it in **System Settings → Privacy &
Security → Accessibility**.

## Using it

1. Open **Settings → General** and record a global shortcut to summon Tinycast.
2. Press it anywhere → the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → App Hotkeys** — search an app and record a shortcut to toggle it.

## Building from source

See **[docs/development.md](docs/development.md)** for the toolchain, build, packaging, release,
and website workflows, and **[docs/ui.md](docs/ui.md)** for the UI design system.

## License

[AGPL-3.0](LICENSE)
