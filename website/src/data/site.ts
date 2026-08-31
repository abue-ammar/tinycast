// Single source of truth for links, install commands, and metadata used across
// the site. Update these in one place rather than hunting through components.

export const site = {
  name: "Tinycast",
  tagline: "The essentials, without the bloat.",
  repo: "https://github.com/abue-ammar/tinycast",
  url: "https://abue-ammar.github.io/tinycast",
  // Shown only until the build-time release lookup resolves, and if it fails.
  fallbackVersion: "v0.9.7",
  platform: "macOS 26+",
  license: "AGPL-3.0",
  licenseUrl: "https://github.com/abue-ammar/tinycast/blob/main/LICENSE",
  community: {
    discord: "https://discord.gg/v2Eeb4QQy3",
  },
  support:
    "https://buy.polar.sh/polar_cl_NDVFC20DKQpLcNawsh97QzbARBXD3WNn8v35R0mbJmT",
} as const;

// The hero, in as few words as possible — headline plus one punchy line.
export const hero = {
  eyebrow: "Native macOS launcher",
  headline: "Everything on your Mac. One keystroke away.",
  sub: "A tiny, native launcher. No Electron. No account. No telemetry. No bullshit.",
} as const;

export const nav = [
  { label: "Gallery", href: "/#gallery" },
  { label: "Features", href: "/#features" },
  { label: "Docs", href: "/docs" },
  { label: "Install", href: "/#install" },
] as const;

// Homebrew install channels. Each is a separate app that runs side by side,
// with its own settings, permissions and login item.
export const channels = [
  {
    id: "stable",
    label: "Stable",
    command:
      "brew trust --tap abue-ammar/tinycast && brew install --cask abue-ammar/tinycast/tinycast",
    note: "Recommended",
  },
  {
    id: "universal",
    label: "Intel",
    command:
      "brew trust --tap abue-ammar/tinycast && brew install --cask abue-ammar/tinycast/tinycast-universal",
    note: "Intel Macs",
  },
  {
    id: "beta",
    label: "Beta",
    command:
      "brew trust --tap abue-ammar/tinycast && brew install --cask abue-ammar/tinycast/tinycast@beta",
    note: "Side-by-side",
  },
  {
    id: "sequoia",
    label: "Sequoia",
    command:
      "brew trust --tap abue-ammar/tinycast && brew install --cask abue-ammar/tinycast/tinycast-sequoia",
    note: "macOS 15",
  },
] as const;

// Only for a direct DMG download. Homebrew clears quarantine on every install
// and update, so the Homebrew path needs no manual step at all.
export const quarantineCommand =
  'xattr -dr com.apple.quarantine "/Applications/Tinycast.app"';

// Headline numbers for the "why it's tiny" band. Kept honest, from the README.
export const stats = [
  { value: "<5", unit: "MB", label: "On disk" },
  { value: "<100", unit: "MB", label: "Memory" },
  { value: "0", unit: "", label: "Dependencies" },
  { value: "0", unit: "", label: "Telemetry" },
] as const;
