// Drives the "Moving over" block. The steps mirror the real import flow
// (Settings → Backup → Raycast Export), and `transfers` matches the app's
// `RaycastImportOptions` exactly — don't add anything the importer can't carry.

export const migration = {
  title: "Bring your Raycast setup with you.",
  intro:
    "Tinycast reads a Raycast export directly. Point it at your .rayconfig file, type the passphrase, and your shortcuts come with you.",
  // Stated up front rather than in the docs alone: a 1.x file is the one thing
  // that will not work, and finding that out mid-import is the bad outcome.
  requirement: {
    title: "Raycast v2.0 and newer only",
    body: "Tinycast reads the .rayconfig that Raycast v2.0 and later write. Raycast v1.x files are not supported — that format was dropped in Tinycast v0.10.5.",
  },
  steps: [
    {
      title: "Export what you have",
      body: "In Raycast, export your settings and data. Note the passphrase you set.",
    },
    {
      title: "Open Settings → Backup",
      body: "Choose the file and type the passphrase. A wrong one is reported as exactly that.",
    },
    {
      title: "Pick what to bring",
      body: "Keep everything, or only the parts you want. That's the whole setup.",
    },
    {
      title: "Quit and reopen Tinycast",
      body: "Quit from the menu-bar icon, not just the Settings window. The import is fully live after that restart.",
    },
  ],
  // Must match RaycastImportOptions in Features/Backup/Model/RaycastImport.swift.
  transfers: [
    "Shortcuts",
    "Favorites",
    "Clipboard history",
    "Snippets",
    "Quicklinks",
    "Aliases",
    "Emoji skin tone",
    "Compact mode",
    "Pop to root",
    "Launch at login",
    "Menu-bar preference",
  ],
} as const;
