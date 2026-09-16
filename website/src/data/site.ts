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
  // One entry per line: the break falls between the two sentences at every
  // width. The last line ends bare, because the hero draws a caret after it.
  headlineLines: ["Everything on your Mac.", "One keystroke away"],
  sub: "A tiny, native launcher. No Electron. No account. No telemetry. No bullshit.",
  // The mono line under the buttons. Each fact is stated in the docs.
  facts: ["Under 100 MB of memory", "Zero dependencies", "Free & open source"],
} as const;

export const nav = [
  { label: "Features", href: "/#features" },
  { label: "Privacy", href: "/#privacy" },
  { label: "Docs", href: "/docs" },
] as const;

// Homebrew install channels. Each is a separate app that runs side by side,
// with its own settings, permissions and login item. Descriptions follow
// docs/install.md.
export const brewTrustCommand = "brew trust --tap abue-ammar/tinycast";

export const channels = [
  {
    id: "stable",
    label: "Stable",
    cask: "tinycast",
    description:
      "Recommended. The smaller build, for Apple silicon on macOS 26.",
  },
  {
    id: "universal",
    label: "Intel",
    cask: "tinycast-universal",
    description:
      "The universal build, for Intel Macs on macOS 26. Runs on Apple silicon too.",
  },
  {
    id: "beta",
    label: "Beta",
    cask: "tinycast@beta",
    description:
      "Installs Tinycast Beta, with its own settings, right beside stable.",
  },
  {
    id: "sequoia",
    label: "Sequoia",
    cask: "tinycast-sequoia",
    description: "For macOS 15 Sequoia. New features reach macOS 26 first.",
  },
] as const;

export function brewInstallCommand(cask: string): string {
  return `brew install --cask abue-ammar/tinycast/${cask}`;
}

// Only for a direct DMG download. Homebrew clears quarantine on every install
// and update, so the Homebrew path needs no manual step at all.
export const quarantineCommand =
  'xattr -dr com.apple.quarantine "/Applications/Tinycast.app"';

// The logo wall under the hero. Order is the render order; the marquee repeats
// the list once so the loop has no seam.
export const companies = [
  "apple",
  "google",
  "microsoft",
  "oracle",
  "bytedance",
  "yandex",
  "redhat",
] as const;

export type Company = (typeof companies)[number];
