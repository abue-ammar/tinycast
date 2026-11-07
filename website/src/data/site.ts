// Single source of truth for links, install commands, and metadata used across
// the site. Update these in one place rather than hunting through components.

// The page title and meta description, shared by the layout and /llms.txt. Google truncates a
// description near 160 characters, so `summary` is written to land under it rather than be cut.
export const pageTitle =
  "Tinycast: a native macOS launcher for everyday productivity";
export const summary =
  "A lightweight, open source macOS launcher with app search, clipboard history, snippets, window management, your own AI keys and Raycast extensions.";

export const site = {
  name: "Tinycast",
  repo: "https://github.com/abue-ammar/tinycast",
  intelTap: "https://github.com/abue-ammar/homebrew-tinycast",
  url: "https://tinycast.dev",
  // The R2 bucket behind cdn.tinycast.dev. Anything over Workers' 25 MiB
  // per-asset cap lives here instead of `public/` — see website/README.md.
  cdn: "https://cdn.tinycast.dev",
  // Shown only until the build-time release lookup resolves, and if it fails.
  fallbackVersion: "v0.9.7",
  platform: "macOS 26+",
  license: "AGPL-3.0",
  licenseUrl: "https://github.com/abue-ammar/tinycast/blob/main/LICENSE",
  community: {
    discord: "https://discord.gg/v2Eeb4QQy3",
  },
  support: "/support",
} as const;

// The hero, in as few words as possible — headline plus one punchy line.
export const hero = {
  // Two lines, the break between the two sentences at every width. The first
  // line opens on each of `swap` in turn, once, and settles on the first, so it
  // ends as written; none is wider than "Everything", so the line never rewraps.
  // The second line ends bare, because the hero draws a caret after it.
  headline: {
    swap: ["Everything", "Every app", "Every file", "Every clip", "Every note"],
    rest: "on your Mac.",
    second: "One keystroke away",
  },
  sub: "A native macOS launcher for everyday productivity. Lightweight and open source, with no account and no telemetry.",
  // The mono line under the buttons. Each fact is stated in the docs.
  facts: ["Under 100 MB of memory", "Zero dependencies", "Free & open source"],
} as const;

export const nav = [
  { label: "Features", href: "/#features" },
  { label: "Privacy", href: "/#privacy" },
  { label: "Docs", href: "/docs" },
  { label: "Changelog", href: "/changelog" },
] as const;

// The hero's line. Every other channel lives in docs/install.md, which is
// where both install CTAs point.
export const brewInstallCommand = "brew install --cask tinycast";

// The logo wall under the hero, in render order. The track starts at the first
// entry with the left edge under the mask, so the two least-known names lead
// and the ones worth reading land mid-viewport on load.
export const companies = [
  "voidzero",
  "bytedance",
  "apple",
  "google",
  "microsoft",
  "openai",
  "anthropic",
  "stripe",
  "cloudflare",
  "github",
  "samsung",
  "alibaba",
  "oracle",
  "redhat",
] as const;

export type Company = (typeof companies)[number];

export type Badge = {
  href: string;
  alt: string;
  src: string;
  darkSrc?: string;
  width: number;
  height: number;
  isInvertedInDark?: boolean;
};

// The images are copies in public/badges, never hotlinks, so the page still
// makes no request to a third party.
export const badges: Badge[] = [
  {
    href: "https://www.star-history.com/abue-ammar/tinycast",
    alt: "GitHub Trending Repository of the Day",
    src: "/badges/trending-light.svg",
    darkSrc: "/badges/trending-dark.svg",
    width: 270,
    height: 64,
  },
  {
    href: "https://usefulshelf.co/apps/tinycast?utm_source=tinycast.dev&utm_medium=referral&utm_campaign=badge&utm_content=light",
    alt: "Featured on UsefulShelf",
    src: "/badges/usefulshelf.svg",
    darkSrc: "/badges/usefulshelf-lime.svg",
    width: 248,
    height: 66,
  },
  {
    href: "https://www.trymacapps.com/app/tinycast",
    alt: "Featured on TryMacApps",
    src: "/badges/trymacapps.png",
    width: 200,
    height: 67,
    // Dark ink on a transparent ground, so it would vanish on the dark canvas.
    isInvertedInDark: true,
  },
];
