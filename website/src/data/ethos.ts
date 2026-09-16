// The closing statement. Every claim here is stated in the docs — Getting
// started, Permissions, Extensions and AI. Don't add one that isn't.

export type EthosPillar = {
  icon: "native" | "local" | "source" | "free";
  title: string;
  body: string;
};

export const ethos = {
  quote: "No account. No telemetry.",
  // Set in italic, so it lands as the punchline rather than a third clause.
  emphasis: "No bullshit.",
  attribution: "the whole privacy policy, more or less",
} as const;

export const ethosPillars: EthosPillar[] = [
  {
    icon: "native",
    title: "Native, end to end",
    body: "SwiftUI and AppKit, Swift 6, zero third-party dependencies. It launches before Electron has finished thinking about it.",
  },
  {
    icon: "local",
    title: "Nothing leaves your Mac",
    body: "No account, no telemetry, no update pings you didn't ask for. AI features are off until you turn them on.",
  },
  {
    icon: "source",
    title: "Open source, AGPL-3.0",
    body: "Read every line. Build it yourself. The feature set is deliberately closed so it stays small.",
  },
  {
    icon: "free",
    title: "Free, and staying free",
    body: "A one-off tip keeps it maintained. There's no Pro tier waiting behind a paywall.",
  },
];
