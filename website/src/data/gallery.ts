// Drives the "Tinycast in action" gallery + lightbox. Each item is a tile in
// the grid and a slide in the lightbox. `src`/`thumb`/`poster` are resolved
// against import.meta.env.BASE_URL in the component, so give plain filenames
// that live in `public/`. `width`/`height` are the media's real pixel size
// (used for lightbox aspect); the grid tile is always 16:9.

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
    src: "tinycast-in-action.mp4",
    poster: "screenshot.png",
    title: "Tinycast in action",
    caption: "A quick tour — launcher, clipboard, calculator, and more.",
    width: 3024,
    height: 1964,
  },
  {
    type: "image",
    src: "calculator.png",
    title: "Inline calculator",
    caption: "Math, unit and currency conversions, right in the palette.",
    width: 2148,
    height: 1302,
  },
  {
    type: "image",
    src: "clipboard.png",
    title: "Clipboard history",
    caption: "Search every text and image you've copied. Always local.",
    width: 2092,
    height: 1268,
  },
  {
    type: "image",
    src: "unlimited-clipboard-history.png",
    title: "Unlimited by default",
    caption: "No Pro tier — keep your full history as long as you like.",
    width: 2226,
    height: 1604,
  },
  {
    type: "image",
    src: "emoji.png",
    title: "Emoji & symbols",
    caption: "Search the whole set; your most-used float to the top.",
    width: 2106,
    height: 1244,
  },
  {
    type: "image",
    src: "per-app-hotkey.png",
    title: "Per-app hotkeys",
    caption: "Bind a key to an app: press to focus, again to hide.",
    width: 2212,
    height: 1606,
  },
  {
    type: "image",
    src: "ram-usage.png",
    title: "Featherweight",
    caption: "Under 100 MB of memory, a few megabytes on disk.",
    width: 2558,
    height: 1754,
  },
  {
    type: "image",
    src: "backup-import-settings.png",
    title: "Backup & import",
    caption: "Export your whole setup, or bring it over from Raycast.",
    width: 2098,
    height: 1600,
  },
];
