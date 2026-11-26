// What people have posted about Tinycast on X, for the "In their own words" wall. Every entry was
// read from its live post: English is quoted as written, minus the trailing t.co link, and a
// Chinese post is our translation, marked by `translatedFrom` and cut with "…" where shortened.
// Avatars are copies in public/testimonials, never hotlinks, so the page makes no request to X.

export type Testimonial = {
  // The post's status id; the card links to it.
  id: string;
  name: string;
  handle: string;
  avatar: string;
  // The UTC date of the post, as X reports it.
  postedAt: string;
  text: string;
  // The post's own link, shown as X shows it: its display text, truncated.
  link?: string;
  translatedFrom?: "Chinese";
};

// Order is placement: each card joins the shortest column, so the first three lead the top row
// and the rest are ordered so the columns end level at two and three across.
export const testimonials: Testimonial[] = [
  {
    id: "2099619102453067917",
    name: "Sindre Sorhus",
    handle: "sindresorhus",
    avatar: "/testimonials/sindresorhus.webp",
    postedAt: "2026-09-14",
    text: "I moved from Raycast since they made it non-native and bad. Tinycast is a great native replacement:",
    link: "github.com/abue-ammar/tin…",
  },
  {
    id: "2099875007383867433",
    name: "Daniel Lockyer",
    handle: "DanielLockyer",
    avatar: "/testimonials/daniellockyer.webp",
    postedAt: "2026-09-15",
    text: "I just switched from Raycast to Tinycast! 🚀",
  },
  {
    id: "2100049070563938482",
    name: "Kyle Gill",
    handle: "gill_kyle",
    avatar: "/testimonials/gill_kyle.webp",
    postedAt: "2026-09-16",
    text: "tinycast is incredible and delivers on the promise of AI making software cheaper.\n\nI've never cared to pay a subscription for my OS launcher, tinycast is an easy migration from Raycast, and carries over virtually every setting",
    link: "github.com/abue-ammar/tin…",
  },
  {
    id: "2082359367320699345",
    name: "Evan Long",
    handle: "evanlong_me",
    avatar: "/testimonials/evanlong_me.webp",
    postedAt: "2026-07-29",
    text: "Another small, beautiful Raycast alternative: Tinycast\n\nA native SwiftUI launcher of only ~3 MB, with no Electron, no account and zero telemetry. …\n\nAs Raycast gets heavier, small native tools that are light enough and do enough are all the more likeable.",
    link: "evanlong.me/share/tinycast",
    translatedFrom: "Chinese",
  },
  {
    id: "2089277457484726362",
    name: "itshan",
    handle: "itshan",
    avatar: "/testimonials/itshan.webp",
    postedAt: "2026-08-17",
    text: "Tinycast — a tiny, fully native macOS launcher, hotkeys, and clipboard history",
    link: "github.com/abue-ammar/tin…",
  },
  {
    id: "2101212229555376310",
    name: "GitHubDaily",
    handle: "GitHub_Daily",
    avatar: "/testimonials/github_daily.webp",
    postedAt: "2026-09-19",
    text: "Tinycast is a fully native macOS launcher. One shortcut opens it, it stays under 100 MB of memory, uses no Electron, collects no data, and is free and open source.\n\n… What surprised me most is that it runs Raycast extensions directly. The ones you already installed just work, drawn as a native interface.",
    translatedFrom: "Chinese",
  },
  {
    id: "2100588650505662826",
    name: "Kyle Gill",
    handle: "gill_kyle",
    avatar: "/testimonials/gill_kyle.webp",
    postedAt: "2026-09-17",
    text: "Still quite satisfied. What a world where a feature like window management isn't locked behind a paywall.\n\nBeauty of open source is that one day when I switch I'll be able to port this to omarchy",
  },
  {
    id: "2081868754930282862",
    name: "AlternativeTo",
    handle: "AlternativeTo",
    avatar: "/testimonials/alternativeto.webp",
    postedAt: "2026-07-27",
    text: "There’s a new completely free and open-source Raycast alternative in town! Swift-native and lightweight, with unlimited clipboard history and per-app hotkeys. No Electron, no telemetry, no background CPU churn",
  },
  {
    id: "2082733686014005408",
    name: "Geek Lite",
    handle: "QingQ77",
    avatar: "/testimonials/qingq77.webp",
    postedAt: "2026-07-30",
    text: "macOS has been missing a light, native launcher and clipboard history tool with no Electron. The alternatives are either big or full of dependencies.\n\nTinycast is a fully native macOS launcher (about 3 MB, under 100 MB of memory), written in Swift with SwiftUI and AppKit, with zero third-party dependencies.",
    translatedFrom: "Chinese",
  },
  {
    id: "2109290927479201953",
    name: "老鬼",
    handle: "laogui",
    avatar: "/testimonials/laogui.webp",
    postedAt: "2026-10-11",
    text: "I've recently replaced Raycast with Tinycast. This thing is practically out to kill Raycast.\n\n… It's written natively in Swift and SwiftUI, with no Electron and no data reporting. AI works with your own key, no subscription needed.",
    translatedFrom: "Chinese",
  },
  {
    id: "2082616664043274687",
    name: "Ding",
    handle: "dingyi",
    avatar: "/testimonials/dingyi.webp",
    postedAt: "2026-07-29",
    text: "A free, open source Raycast alternative. It can import all of your settings from Raycast.",
    translatedFrom: "Chinese",
  },
];

export function postUrl({ handle, id }: Testimonial) {
  return `https://x.com/${handle}/status/${id}`;
}
