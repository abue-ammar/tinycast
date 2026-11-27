import type { IconName } from "../components/ui/feature-icons";

// Every claim here is stated in the docs: Getting started, Settings → Features,
// Permissions, AI, Snippets, Calendar and Clipboard. Don't add one that isn't.

export const privacyStats = [
  { value: "0", label: "accounts" },
  { value: "0", label: "telemetry" },
  { value: "0", label: "dependencies" },
  { value: "<100 MB", label: "of memory" },
] as const;

export type DefaultSwitch = {
  icon: IconName;
  name: string;
  note: string;
  isOn: boolean;
};

// Mirrors the Features table in docs/reference/settings: everything ships off
// except Clipboard (and Emoji, which has no switch).
export const defaultSwitches: DefaultSwitch[] = [
  {
    icon: "aiChat",
    name: "AI",
    note: "The chat command and its history file don't exist until you turn AI on.",
    isOn: false,
  },
  {
    icon: "snippets",
    name: "Snippets",
    note: "The only feature that reads what you type. Matching happens on your Mac.",
    isOn: false,
  },
  {
    icon: "calendar",
    name: "Calendar",
    note: "Tells you what it reads before macOS asks for access. Events stay on your Mac.",
    isOn: false,
  },
  {
    icon: "clipboard",
    name: "Clipboard history",
    note: "Stored on your Mac for 3 months. Ignores copies from Keychain Access and Passwords.",
    isOn: true,
  },
];

export const permissionNote =
  "Tinycast asks for a permission only when a feature first needs it, never at launch. Restoring a settings backup can't turn on snippets.";
