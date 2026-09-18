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
  /** Spans two columns of the bento on wide screens. */
  isWide: boolean;
};

export type MinorFeature = Pick<Feature, "icon" | "title" | "href">;

// Everything Tinycast does, in plain language. Kept true to what the app
// actually ships — each maps to a real feature in the source, and each links
// to the docs page that covers it. Order sets the bento: every row adds up to
// four columns, with wide cards counting as two.
export const coreFeatures: Feature[] = [
  {
    icon: "launch",
    title: "App launcher",
    body: "Fuzzy-search every app and open it with a keystroke. Pin favorites, see what's running, restart or quit without the mouse.",
    href: "/docs/launcher",
    preview: "launcher",
    isWide: true,
  },
  {
    icon: "calculator",
    title: "Inline calculator",
    body: "Math, units, live currency, time zones and dates like “days till 9 Apr”.",
    href: "/docs/features/calculator",
    preview: "calculator",
    isWide: false,
  },
  {
    icon: "clipboard",
    title: "Clipboard history",
    body: "Text, images, files and colors, searchable and pasted straight back.",
    href: "/docs/features/clipboard",
    preview: "clipboard",
    isWide: false,
  },
  {
    icon: "aiChat",
    title: "AI Chat",
    body: "Apple Intelligence, Codex, Claude, Grok, OpenCode or any API you bring.",
    href: "/docs/ai",
    preview: "aiChat",
    isWide: false,
  },
  {
    icon: "quickActions",
    title: "Quick Actions",
    body: "Select text in any app and fix, rewrite, translate or summarize it.",
    href: "/docs/ai/quick-actions",
    preview: "quickActions",
    isWide: false,
  },
  {
    icon: "windows",
    title: "Window management",
    body: "Halves, thirds, nudges, display moves and saved layouts, all from the keyboard. 34 commands.",
    href: "/docs/features/window-management",
    preview: "windows",
    isWide: true,
  },
  {
    icon: "extensions",
    title: "Raycast extensions",
    body: "Run in JavaScriptCore and drawn in SwiftUI. Install from the store with no toolchain.",
    href: "/docs/extensions",
    preview: "extensions",
    isWide: true,
  },
  {
    icon: "snippets",
    title: "Snippets",
    body: "Markdown templates with placeholders. Type a keyword in any app and it expands.",
    href: "/docs/features/snippets",
    preview: "snippets",
    isWide: true,
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
    title: "31 system actions",
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
