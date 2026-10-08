// Drives the "Tinycast in action" gallery + lightbox. Each item is a tile in
// the grid and a slide in the lightbox. `src`/`thumb`/`poster` are URLs as
// rendered — root-absolute for `public/`, absolute for anything on R2.
// `width`/`height` are the media's real pixel size (used for lightbox aspect);
// the grid tile is always 16:9.

import { site } from "./site";

export type GalleryItem = {
  type: "image" | "video";
  // Full-size media shown in the lightbox (image src, or video file for clips).
  src: string;
  // Grid thumbnail; falls back to `poster` (video) or `src` (image).
  thumb?: string;
  // Poster frame for video tiles/slides.
  poster?: string;
  title: string;
  caption: string;
  width: number;
  height: number;
};

export const galleryItems: GalleryItem[] = [
  {
    type: "video",
    src: `${site.cdn}/calculator.mp4`,
    poster: "/calculator.jpg",
    title: "Inline calculator",
    caption: "Answers math and converts units and currencies as you type.",
    width: 1728,
    height: 1118,
  },
  {
    type: "image",
    src: "/clipboard-history.jpg",
    title: "Clipboard history",
    caption:
      "Search the text and images you've copied. History is stored only on your Mac.",
    width: 3359,
    height: 2171,
  },
  {
    type: "video",
    src: `${site.cdn}/dictation.mp4`,
    poster: "/dictation.jpg",
    title: "Dictation",
    caption:
      "Turn your voice into text in any app. Fast, private and fully on-device.",
    width: 1728,
    height: 1118,
  },
  {
    type: "video",
    src: `${site.cdn}/emoji-and-symbols.mp4`,
    poster: "/emoji-and-symbols.jpg",
    title: "Emoji & symbols",
    caption: "Search every emoji. The ones you use most show up first.",
    width: 1728,
    height: 1118,
  },
  {
    type: "video",
    src: `${site.cdn}/notes.mp4`,
    poster: "/notes.jpg",
    title: "Notes",
    caption:
      "Capture ideas in Markdown. Keep your notes close, without breaking your flow.",
    width: 1728,
    height: 1118,
  },
  {
    type: "video",
    src: `${site.cdn}/quick-ai.mp4`,
    poster: "/quick-ai.jpg",
    title: "Quick AI",
    caption:
      "Ask your favorite AI. Get quick answers or open a full chat with history.",
    width: 1728,
    height: 1118,
  },
  {
    type: "video",
    src: `${site.cdn}/quick-actions.mp4`,
    poster: "/quick-actions.jpg",
    title: "Quick Actions",
    caption:
      "Rewrite, translate, summarize and more with AI. Create your own custom actions.",
    width: 1728,
    height: 1118,
  },
  {
    type: "image",
    src: "/activity-monitor.jpg",
    title: "Light on memory",
    caption: "Stays under 100 MB of memory, no matter how long it runs.",
    width: 3359,
    height: 2171,
  },
];
