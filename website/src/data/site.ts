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

// The hero's two lines. Every other channel lives in docs/install.md, which is
// where both install CTAs point.
export const brewTrustCommand = "brew trust --tap abue-ammar/tinycast";
export const brewInstallCommand =
  "brew install --cask abue-ammar/tinycast/tinycast";

// The logo wall under the hero. Order is the render order; the marquee repeats
// the list once so the loop has no seam.
export const companies = [
  "apple",
  "google",
  "microsoft",
  "openai",
  "anthropic",
  "stripe",
  "cloudflare",
  "github",
  "oracle",
  "samsung",
  "alibaba",
  "bytedance",
  "redhat",
  "voidzero",
] as const;

export type Company = (typeof companies)[number];
