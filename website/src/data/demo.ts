// The hero's recreated palette. Labels copy the real app's strings (the action
// bar, section titles, placeholders), and every row names Tinycast's own
// things or generic apps, so nothing here pretends to be someone's data.

export type DemoRowIcon = "ghost" | "github" | "link" | "file" | "terminal";

export type DemoRow = {
  title: string;
  kind: string;
  icon: DemoRowIcon;
  /** CSS background for the icon tile. */
  tint: string;
};

export type DemoSection = {
  title: string;
  rows: DemoRow[];
};

export const demoQuery = "gh";
export const demoAction = "Open Application";

export const demoSections: DemoSection[] = [
  {
    title: "Favorites",
    rows: [
      {
        title: "Ghostty",
        kind: "Application",
        icon: "ghost",
        tint: "linear-gradient(160deg, #3d5afe, #0d1b6e)",
      },
      {
        title: "GitHub Desktop",
        kind: "Application",
        icon: "github",
        tint: "linear-gradient(160deg, #a875ff, #5b12bd)",
      },
    ],
  },
  {
    title: "Applications",
    rows: [
      {
        title: "Search GitHub",
        kind: "Quicklink",
        icon: "link",
        tint: "linear-gradient(160deg, #47bfff, #1769aa)",
      },
      {
        title: "gh pr checkout",
        kind: "Command",
        icon: "terminal",
        tint: "linear-gradient(160deg, #6b6d72, #2a2b2e)",
      },
      {
        title: "Ghostty config",
        kind: "File",
        icon: "file",
        tint: "linear-gradient(160deg, #863bff, #7e14ff)",
      },
    ],
  },
];
