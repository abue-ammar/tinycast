<h1 align="center">
  <a href="https://tinycast.dev"><img src="docs/images/icon.png" alt="Tinycast app icon" width="128" height="128"></a><br>
  Tinycast
</h1>

<p align="center">
  A native macOS launcher for everyday productivity. Lightweight and open source.
</p>

<p align="center">
  <a href="https://tinycast.dev"><strong>Website</strong></a> ·
  <a href="#install"><strong>Install</strong></a> ·
  <a href="https://tinycast.dev/docs/"><strong>Docs</strong></a> ·
  <a href="https://tinycast.dev/support"><strong>Support</strong></a>
</p>

<p align="center">
  <a href="https://github.com/abue-ammar/tinycast/releases/latest"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/release/abue-ammar/tinycast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;label=RELEASE&amp;logo=lu:Tag&amp;valueColor=60A5FA" /><img alt="Latest release" src="https://shieldcn.dev/github/release/abue-ammar/tinycast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;label=RELEASE&amp;logo=lu:Tag&amp;valueColor=2563EB" /></picture></a>
  <a href="https://github.com/abue-ammar/tinycast/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/downloads/abue-ammar/tinycast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;label=DOWNLOADS&amp;logo=lu:CloudDownload&amp;valueColor=A78BFA" /><img alt="Total downloads" src="https://shieldcn.dev/github/downloads/abue-ammar/tinycast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;label=DOWNLOADS&amp;logo=lu:CloudDownload&amp;valueColor=7C3AED" /></picture></a>
  <a href="https://github.com/abue-ammar/tinycast/actions/workflows/release.yml"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/github/ci/abue-ammar/tinycast.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;workflow=release.yml&amp;label=BUILD&amp;logo=lu:Hammer&amp;valueColor=4ADE80" /><img alt="Release build status" src="https://shieldcn.dev/github/ci/abue-ammar/tinycast.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;workflow=release.yml&amp;label=BUILD&amp;logo=lu:Hammer&amp;valueColor=16A34A" /></picture></a>
  <a href="https://discord.gg/v2Eeb4QQy3"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/DISCORD-JOIN.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=discord&amp;valueColor=A5B4FC" /><img alt="Join the Tinycast Discord" src="https://shieldcn.dev/badge/DISCORD-JOIN.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=discord&amp;valueColor=5865F2" /></picture></a>
  <br>
  <picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/MACOS-26%2B.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=apple" /><img alt="macOS 26 or later" src="https://shieldcn.dev/badge/MACOS-26%2B.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=apple" /></picture>
  <picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/SWIFT-6.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=swift&amp;valueColor=FB923C" /><img alt="Swift 6" src="https://shieldcn.dev/badge/SWIFT-6.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=swift&amp;valueColor=EA580C" /></picture>
  <a href="LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/LICENSE-AGPL--3.0.svg?variant=ghost&amp;font=geist-mono&amp;mode=dark&amp;logo=lu:Scale" /><img alt="License: AGPL-3.0" src="https://shieldcn.dev/badge/LICENSE-AGPL--3.0.svg?variant=ghost&amp;font=geist-mono&amp;mode=light&amp;logo=lu:Scale" /></picture></a>
</p>

<p align="center">
  <img src="docs/screenshot.jpg" alt="Tinycast command palette">
</p>

Built with SwiftUI and AppKit. No dependencies, no Electron, no telemetry. It runs your Raycast
extensions, too.

[Explore all features →](https://tinycast.dev/#features)

For anything private, feel free to email [iabueammar@gmail.com](mailto:iabueammar@gmail.com).

## Install

On an Apple silicon Mac with macOS 26 or newer:

```sh
brew install --cask tinycast
brew install --cask tinycast@beta
```

- **DMG:** notarized, download from [Releases](https://github.com/abue-ammar/tinycast/releases). Drag `Tinycast.app` to `/Applications`.
- **Intel Mac:** install from [Homebrew tap](https://github.com/abue-ammar/homebrew-tinycast).

## Support

Tinycast is free and stays free. If it earns a place on your Mac, consider supporting its
development. Thank you!

<p align="center">
  <a href="https://tinycast.dev/support"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/SUPPORT-CARD.svg?variant=outline&amp;size=lg&amp;font=geist-mono&amp;mode=dark&amp;logo=lu:CircleDollarSign&amp;logoColor=A78BFA&amp;valueColor=A78BFA" /><img alt="Support by card payment" src="https://shieldcn.dev/badge/SUPPORT-CARD.svg?variant=outline&amp;size=lg&amp;font=geist-mono&amp;mode=light&amp;logo=lu:CircleDollarSign&amp;logoColor=7C3AED&amp;valueColor=7C3AED" /></picture></a>
  <a href="https://tinycast.dev/support?method=crypto"><picture><source media="(prefers-color-scheme: dark)" srcset="https://shieldcn.dev/badge/SUPPORT-CRYPTO.svg?variant=outline&amp;size=lg&amp;font=geist-mono&amp;mode=dark&amp;logo=lu:Bitcoin&amp;logoColor=FBBF24&amp;valueColor=FBBF24" /><img alt="Support with crypto" src="https://shieldcn.dev/badge/SUPPORT-CRYPTO.svg?variant=outline&amp;size=lg&amp;font=geist-mono&amp;mode=light&amp;logo=lu:Bitcoin&amp;logoColor=B45309&amp;valueColor=B45309" /></picture></a>
</p>

## License

Tinycast is licensed under the [AGPL-3.0 license](LICENSE).
