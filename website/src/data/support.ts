// Copy for /support. Amounts are whole US dollars; the Worker turns them into Polar's cents.

export type Plan = "monthly" | "one-time";

export const supportHero = {
  eyebrow: "Support",
  title: "Enjoying Tinycast?",
  intro:
    "Tinycast is free and open source, and it stays that way. If it earns a place on your Mac, buy the wallpaper pack or send some crypto. Either one helps me a lot. Thanks.",
} as const;

export type Wallet = {
  id: string;
  // The picker's short name; `network` is the precise one the warning needs.
  label: string;
  network: string;
  address: string;
};

// Each id names its mark and QR code in public/wallets/; a code encodes its address verbatim.
export const wallets: readonly Wallet[] = [
  {
    id: "bitcoin",
    label: "Bitcoin",
    network: "Bitcoin",
    address: "bc1qpfxtjpuhm2cm8kg4lqgu3ffjch7vcjf678arwn",
  },
  {
    id: "ethereum",
    label: "Ethereum",
    network: "Ethereum",
    address: "0x22A00612bc0bf1Dc73AAC75e8De1BA4e81fF0810",
  },
  {
    id: "solana",
    label: "Solana",
    network: "Solana",
    address: "4EH7JDXZxkJiahas1xgPyC1iBW9pfCVUXxVtpqvwAz6T",
  },
  {
    id: "base",
    label: "Base",
    network: "Base",
    address: "0x22A00612bc0bf1Dc73AAC75e8De1BA4e81fF0810",
  },
  {
    id: "bnb",
    label: "BNB Chain",
    network: "BNB Smart Chain",
    address: "0x22A00612bc0bf1Dc73AAC75e8De1BA4e81fF0810",
  },
];

export type Method = "crypto" | "card";

export const methods: { id: Method; label: string }[] = [
  { id: "card", label: "Card" },
  { id: "crypto", label: "Crypto" },
];

export const cryptoSupport = {
  intro: "Pick a network, then scan the code or copy the address.",
  warning: (network: string) =>
    `Send only on the ${network} network. Funds sent on another network may be lost.`,
  unlisted: {
    lead: "Network not listed? Email",
    email: "iabueammar@gmail.com",
    subject: "Supporting Tinycast",
  },
} as const;

export const cardSupport = {
  intro: "Buy the wallpaper pack and get a Discord role.",
} as const;

export const plans: { id: Plan; label: string }[] = [
  { id: "one-time", label: "One-time" },
  { id: "monthly", label: "Monthly" },
];

export const presetAmounts = [5, 10, 25, 50] as const;
export const maxAmount = 10_000;

export const thanks = {
  title: "Thank you.",
  body: "Your wallpapers are ready.",
  next: {
    monthly: [
      "Polar has emailed your receipt.",
      "Your subscription renews each month until canceled. Change or cancel it anytime in your Polar customer portal.",
    ],
    "one-time": [
      "Polar has emailed your receipt.",
      "This was a one-time payment, so nothing will renew.",
    ],
  },
  perks: {
    title: "Download your wallpapers",
    body: "Sign in with your checkout email to download the pack and connect Discord to get your role.",
    action: "Open your Polar portal",
    // Polar's customer portal for the tinycast organization; perks are claimed there.
    href: "https://polar.sh/tinycast/portal",
  },
  share: "Know someone who lives in Spotlight? Tell them about Tinycast.",
} as const satisfies {
  title: string;
  body: string;
  next: Record<Plan, readonly string[]>;
  perks: { title: string; body: string; action: string; href: string };
  share: string;
};
