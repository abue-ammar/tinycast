// The closing statement. Every claim here is stated in the docs — Getting
// started, Permissions and AI. Don't add one that isn't.

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
    title: "Native",
    body: "Written in Swift 6 with SwiftUI and AppKit, and no third-party dependencies. It opens fast and stays under 100 MB of memory.",
  },
  {
    icon: "local",
    title: "Local",
    body: "Your clipboard, notes and snippets are stored on your Mac. AI stays off until you turn it on and pick a provider.",
  },
  {
    icon: "source",
    title: "Open source",
    body: "The full source is on GitHub under AGPL-3.0, and you can build it yourself. The scope stays narrow so the app stays small.",
  },
  {
    icon: "free",
    title: "Free",
    body: "Every feature is free, and there is no Pro tier. Optional tips pay the running costs.",
  },
];
