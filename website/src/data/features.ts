import type { IconName } from "../components/ui/feature-icons";

export type Feature = {
  icon: IconName;
  title: string;
  body: string;
  /** Deep link into the docs page that covers this feature. */
  href: string;
  // `wide` features span two columns in the bento grid.
  wide?: boolean;
};

// Everything Tinycast does, in plain language. Kept true to what the app
// actually ships — each maps to a real feature in the source, and each links
// to the docs page that covers it.
export const features: Feature[] = [
  {
    icon: "launch",
    title: "App launcher",
    body: "Fuzzy-search every app on your Mac and open it with a keystroke. Pin the ones you reach for, see what's already running, and quit an app without leaving the keyboard.",
    href: "/docs/launcher",
    wide: true,
  },
  {
    icon: "extensions",
    title: "Extensions",
    body: "Runs Raycast extensions natively, rendered as SwiftUI. Install from the store without a toolchain, or bring over the ones you already have.",
    href: "/docs/extensions",
  },
  {
    icon: "clipboard",
    title: "Clipboard history",
    body: "Text and images, full-text searchable, filtered by type, pasted straight back where you came from — kept as long as you like, up to forever.",
    href: "/docs/features/clipboard",
  },
  {
    icon: "calculator",
    title: "Inline calculator",
    body: "Math, unit, live currency and crypto conversions right in the palette — plus plain-English dates like “days till 9 Apr”.",
    href: "/docs/features/calculator",
  },
  {
    icon: "snippets",
    title: "Snippets",
    body: "Reusable Markdown templates with placeholders, arguments and nested references. Type a keyword in any app and it expands.",
    href: "/docs/features/snippets",
  },
  {
    icon: "notes",
    title: "Floating notes",
    body: "Plain Markdown files in one floating editor. No database, no frontmatter — the file on disk is exactly what you typed.",
    href: "/docs/features/notes",
  },
  {
    icon: "fileSearch",
    title: "File search",
    body: "Find files and folders through the Spotlight index, only when you ask. Needs no file permission at all.",
    href: "/docs/features/file-search",
  },
  {
    icon: "windows",
    title: "Window management",
    body: "Halves, quarters, thirds, nudges, display moves and instant Space switching — 32 commands, with no new permission and nothing new to install.",
    href: "/docs/features/window-management",
  },
  {
    icon: "quicklinks",
    title: "Quicklinks",
    body: "Turn a URL, search, file or deeplink into a real command, with arguments it prompts you for and a chosen app to open it in.",
    href: "/docs/launcher/quicklinks",
  },
  {
    icon: "keyboard",
    title: "Custom commands",
    body: "Name a shell command and run it from search or its own global hotkey. Every run confirms first.",
    href: "/docs/launcher/commands",
  },
  {
    icon: "bolt",
    title: "System actions",
    body: "Lock, sleep, restart, volume, Bluetooth, Stage Manager, empty the Trash — 31 actions, each bindable to a key.",
    href: "/docs/launcher/system-actions",
  },
  {
    icon: "emoji",
    title: "Emoji & symbols",
    body: "Search the full emoji and symbol set, tune the skin tone, and your most-used ones float to the top.",
    href: "/docs/features/emoji",
  },
  {
    icon: "globe",
    title: "Global & per-app hotkeys",
    body: "Record a shortcut to summon the palette, bind a key to any app to focus or hide it, or double-tap a lone modifier.",
    href: "/docs/reference/hotkeys",
  },
  {
    icon: "hyper",
    title: "Hyper key",
    body: "Turn Caps Lock or a right-side modifier into ⌃⌥⇧⌘ — a whole extra layer of shortcuts, shown as a single ✦.",
    href: "/docs/reference/hotkeys",
  },
  {
    icon: "alias",
    title: "Aliases",
    body: "Rename anything in the launcher. An alias matches as strongly as the real name, so “ps” can open Photoshop.",
    href: "/docs/launcher/aliases",
  },
  {
    icon: "uninstall",
    title: "App uninstaller",
    body: "Remove an app and the caches, preferences and containers it leaves behind. Everything goes to the Trash, never deleted.",
    href: "/docs/launcher/uninstall",
  },
  {
    icon: "inputSource",
    title: "Input source switching",
    body: "Switch the keyboard to a chosen source while the palette is open, and put it back when you leave.",
    href: "/docs/palette",
  },
  {
    icon: "appearance",
    title: "Light & Dark",
    body: "Follow macOS, or pin Tinycast to Light or Dark. Same design either way — only the ink inverts.",
    href: "/docs/reference/settings",
  },
  {
    icon: "backup",
    title: "Backup & restore",
    body: "Export every shortcut, favorite and clip to one file, then restore it on another Mac. A backup can never grant a permission.",
    href: "/docs/reference/backup",
  },
];
