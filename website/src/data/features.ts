import type { IconName } from "../components/ui/feature-icons";

export type Feature = {
  icon: IconName;
  title: string;
  body: string;
  // `wide` features span two columns in the bento grid.
  wide?: boolean;
};

// Everything Tinycast does, in plain language. Kept true to what the app
// actually ships — each maps to a real feature in the source.
export const features: Feature[] = [
  {
    icon: "launch",
    title: "App launcher",
    body: "Fuzzy-search every app on your Mac and open it with a keystroke. Pin the ones you reach for, and see what's already running at a glance.",
    wide: true,
  },
  {
    icon: "clipboard",
    title: "Clipboard history",
    body: "Text and images, full-text searchable, pasted straight back where you came from — kept as long as you like, up to forever.",
  },
  {
    icon: "calculator",
    title: "Inline calculator",
    body: "Type math, unit or live currency conversions right in the palette, read the answer as you go, and revisit past results from history.",
  },
  {
    icon: "emoji",
    title: "Emoji & symbols",
    body: "Search the full emoji and symbol set, tune the skin tone, and your most-used ones float to the top.",
  },
  {
    icon: "globe",
    title: "Global hotkey",
    body: "One shortcut summons the palette from anywhere — over any app, full-screen or not.",
  },
  {
    icon: "bolt",
    title: "Per-app hotkeys",
    body: "Bind a key to an app to toggle it: press once to focus, again to hide.",
  },
  {
    icon: "hyper",
    title: "Hyper key",
    body: "Turn Caps Lock into a ⌃⌥⇧⌘ super-modifier — a whole extra layer of shortcuts, shown as a single ✦.",
  },
  {
    icon: "backup",
    title: "Backup & restore",
    body: "Export every shortcut, favorite, and clip to one file, then restore it on any Mac.",
  },
];
