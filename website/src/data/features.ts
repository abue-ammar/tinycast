import type { IconName } from "../components/ui/feature-icons";

export type FeaturePreview =
  | "launcher"
  | "extensions"
  | "clipboard"
  | "calculator"
  | "aiChat"
  | "quickActions"
  | "windows"
  | "snippets";

export type Feature = {
  icon: IconName;
  title: string;
  body: string;
  /** Deep link into the docs page that covers this feature. */
  href: string;
  preview: FeaturePreview;
};

export type MinorFeature = Pick<Feature, "icon" | "title" | "href">;

// Everything Tinycast does, in plain language. Kept true to what the app
// actually ships — each maps to a real feature in the source, and each links
// to the docs page that covers it. Order is the showcase's tab order.
export const coreFeatures: Feature[] = [
  {
    icon: "launch",
    title: "App launcher",
    body: "Open any app in a few keystrokes. Pin favorites, and quit or restart running apps.",
    href: "/docs/launcher",
    preview: "launcher",
  },
  {
    icon: "calculator",
    title: "Inline calculator",
    body: "Math, units, currencies, time zones, and dates like “days till 9 Apr”.",
    href: "/docs/features/calculator",
    preview: "calculator",
  },
  {
    icon: "clipboard",
    title: "Clipboard history",
    body: "Search the text, images, files and colors you've copied, then paste them back.",
    href: "/docs/features/clipboard",
    preview: "clipboard",
  },
  {
    icon: "aiChat",
    title: "AI Chat",
    body: "Use Apple Intelligence, Claude, Codex, Cursor, Grok, OpenCode or your own API key.",
    href: "/docs/ai",
    preview: "aiChat",
  },
  {
    icon: "quickActions",
    title: "Quick Actions",
    body: "Select text in any app and fix, rewrite, translate or summarize it.",
    href: "/docs/ai/quick-actions",
    preview: "quickActions",
  },
  {
    icon: "windows",
    title: "Window management",
    body: "35 keyboard commands for halves, thirds, nudges and displays, plus saved layouts.",
    href: "/docs/features/window-management",
    preview: "windows",
  },
  {
    icon: "extensions",
    title: "Raycast extensions",
    body: "Install from the Raycast Store with no Node or build step. They render in SwiftUI.",
    href: "/docs/extensions",
    preview: "extensions",
  },
  {
    icon: "snippets",
    title: "Snippets",
    body: "Type a keyword in any app to expand it into text, with Markdown and placeholders.",
    href: "/docs/features/snippets",
    preview: "snippets",
  },
];

// The long tail: named, linked, and kept out of the way of the eight above.
export const moreFeatures: MinorFeature[] = [
  { icon: "notes", title: "Floating notes", href: "/docs/features/notes" },
  {
    icon: "fileSearch",
    title: "File search",
    href: "/docs/features/file-search",
  },
  {
    icon: "calendar",
    title: "Calendar & meetings",
    href: "/docs/features/calendar",
  },
  {
    icon: "navigation",
    title: "Window & menu search",
    href: "/docs/features/navigation",
  },
  {
    icon: "quicklinks",
    title: "Quicklinks",
    href: "/docs/launcher/quicklinks",
  },
  {
    icon: "keyboard",
    title: "Custom commands",
    href: "/docs/launcher/commands",
  },
  {
    icon: "bolt",
    title: "32 system actions",
    href: "/docs/launcher/system-actions",
  },
  { icon: "emoji", title: "Emoji & symbols", href: "/docs/features/emoji" },
  { icon: "globe", title: "Per-app hotkeys", href: "/docs/reference/hotkeys" },
  { icon: "hyper", title: "Hyper key", href: "/docs/reference/hotkeys" },
  { icon: "alias", title: "Aliases", href: "/docs/launcher/aliases" },
  {
    icon: "uninstall",
    title: "App uninstaller",
    href: "/docs/launcher/uninstall",
  },
  {
    icon: "inputSource",
    title: "Input source switching",
    href: "/docs/palette#input-source",
  },
  {
    icon: "appearance",
    title: "Light, Dark and glass",
    href: "/docs/palette#appearance",
  },
  { icon: "backup", title: "Backup & restore", href: "/docs/reference/backup" },
];
