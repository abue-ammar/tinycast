"use client";

import { Play } from "lucide-react";
import dynamic from "next/dynamic";
import Image from "next/image";
import { useEffect, useState } from "react";
import type { Slide } from "yet-another-react-lightbox";
import { galleryItems, type GalleryItem } from "../data/gallery";
import { cn } from "../lib/cn";
import { Section } from "./ui/section";

// The lightbox is ~30 KB gzipped and does nothing until a tile is clicked.
const GalleryLightbox = dynamic(() => import("./gallery-lightbox"));

// The grid thumbnail: an explicit thumb, else a video's poster, else the image.
const tileImage = (item: GalleryItem) =>
  item.thumb ?? (item.type === "video" ? (item.poster ?? item.src) : item.src);

// One gallery item → one lightbox slide. Images carry title/description for the
// Captions plugin; videos use the Video plugin's `sources` shape.
function toSlide(item: GalleryItem): Slide {
  if (item.type === "video") {
    return {
      type: "video",
      poster: item.poster,
      width: item.width,
      height: item.height,
      title: item.title,
      description: item.caption,
      sources: [{ src: item.src, type: "video/mp4" }],
    };
  }
  return {
    src: item.src,
    title: item.title,
    description: item.caption,
    width: item.width,
    height: item.height,
  };
}

export function Gallery() {
  const [index, setIndex] = useState(-1);
  // Once opened, keep it mounted so closing and reopening costs no fetch.
  const [everOpened, setEverOpened] = useState(false);

  function open(i: number) {
    setEverOpened(true);
    setIndex(i);
  }

  // Lock scroll ourselves instead of via the lightbox's own module: it pads the
  // scrollbar width onto <body> and every fixed element (the scroll-top button
  // included, shifting its arrow). `scrollbar-gutter: stable` already reserves
  // that space, so a plain overflow:hidden lock changes no widths — no shift.
  useEffect(() => {
    if (index < 0) return;
    const html = document.documentElement;
    const previous = html.style.overflow;
    html.style.overflow = "hidden";
    return () => {
      html.style.overflow = previous;
    };
  }, [index]);

  return (
    <Section
      id="gallery"
      index={2}
      label="In action"
      title="The real app, not a mockup."
      intro="The palette up top is a recreation. These are captured from Tinycast itself. Open any of them full size."
    >
      <div className="overflow-hidden rounded-xl border border-border/70 bg-surface shadow-xs">
        <div className="flex min-h-11 items-center gap-3 border-b border-border/60 px-4 py-1.5 font-mono text-micro uppercase text-fg-muted">
          <span
            aria-hidden="true"
            className="size-1.5 rounded-full bg-violet"
          />
          Captured in Tinycast
          <span className="ml-auto hidden sm:inline">Click any to enlarge</span>
        </div>
        {/* The tour video leads at double size and the last still runs double
            width, so the stills fill every row without a gap. */}
        <div className="grid gap-3 p-3 sm:grid-cols-2 lg:grid-cols-4">
          {galleryItems.map((item, i) => {
            const isLead = i === 0;
            const isLast = i === galleryItems.length - 1;
            return (
              <button
                key={`${item.title}-${i}`}
                type="button"
                onClick={() => open(i)}
                className={cn(
                  "group flex flex-col gap-2 text-left",
                  isLead && "sm:col-span-2 lg:row-span-2",
                  isLast && "sm:col-span-2",
                )}
              >
                <figure
                  className={cn(
                    "relative aspect-video w-full overflow-hidden rounded-lg ring-1 ring-border/60 transition-shadow duration-200 group-hover:ring-border-strong",
                    (isLead || isLast) && "lg:aspect-auto lg:flex-1",
                  )}
                >
                  <Image
                    src={tileImage(item)}
                    alt={item.title}
                    fill
                    sizes={
                      isLead || isLast
                        ? "(min-width: 640px) 50vw, 90vw"
                        : "(min-width: 1024px) 25vw, (min-width: 640px) 45vw, 90vw"
                    }
                    className="object-cover transition-transform duration-300 group-hover:scale-[1.02]"
                  />
                  {item.type === "video" && (
                    <span className="absolute inset-0 flex items-center justify-center">
                      <span className="flex size-16 items-center justify-center rounded-full bg-fg text-canvas transition-transform duration-200 group-hover:scale-105">
                        <Play size={24} fill="currentColor" />
                      </span>
                    </span>
                  )}
                </figure>
                <div>
                  <h3 className="text-small font-medium text-fg">
                    {item.title}
                  </h3>
                  <p className="text-small text-fg-muted">{item.caption}</p>
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {everOpened && (
        <GalleryLightbox
          index={index}
          slides={galleryItems.map(toSlide)}
          close={() => setIndex(-1)}
        />
      )}
    </Section>
  );
}
