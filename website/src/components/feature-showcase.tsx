"use client";

import { ArrowUpRight } from "lucide-react";
import Link from "next/link";
import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import type { Feature } from "../data/features";
import { cn } from "../lib/cn";
import { FeatureScene } from "./feature-scenes";
import { featureIcons } from "./ui/feature-icons";

const keyMoves: Record<string, (index: number, count: number) => number> = {
  ArrowDown: (i, n) => (i + 1) % n,
  ArrowRight: (i, n) => (i + 1) % n,
  ArrowUp: (i, n) => (i - 1 + n) % n,
  ArrowLeft: (i, n) => (i - 1 + n) % n,
  Home: () => 0,
  End: (_, n) => n - 1,
};

// A tab list styled as the palette's own result rows. It advances on its own
// until someone picks a row; from then on the reader is in charge.
export function FeatureShowcase({ features }: { features: Feature[] }) {
  const [active, setActive] = useState(0);
  const [isAutoplay, setIsAutoplay] = useState(true);
  const [isPaused, setIsPaused] = useState(false);
  const [isOffscreen, setIsOffscreen] = useState(true);
  const root = useRef<HTMLDivElement>(null);
  const tabs = useRef<(HTMLButtonElement | null)[]>([]);
  const id = useId();

  useEffect(() => {
    const element = root.current;
    if (!element) return;
    const observer = new IntersectionObserver(
      ([entry]) => setIsOffscreen(!entry.isIntersecting),
      { threshold: 0.35 },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  function choose(index: number) {
    setIsAutoplay(false);
    setActive(index);
  }

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const move = keyMoves[event.key];
    if (!move) return;
    event.preventDefault();
    const next = move(active, features.length);
    choose(next);
    tabs.current[next]?.focus();
  }

  const feature = features[active];

  return (
    <div
      ref={root}
      className="feature-showcase grid items-start gap-2 rounded-2xl bg-tint/4 p-2 lg:grid-cols-[18rem_minmax(0,1fr)]"
      data-paused={isPaused || undefined}
      data-offscreen={isOffscreen || undefined}
      onPointerEnter={() => setIsPaused(true)}
      onPointerLeave={() => setIsPaused(false)}
      onFocus={() => setIsPaused(true)}
      onBlur={() => setIsPaused(false)}
    >
      <div
        role="tablist"
        aria-label="Features"
        aria-orientation="vertical"
        onKeyDown={onKeyDown}
        className="flex gap-1 overflow-x-auto [scrollbar-width:none] lg:flex-col lg:overflow-visible"
      >
        {features.map((item, index) => {
          const Icon = featureIcons[item.icon];
          const isActive = index === active;
          return (
            <button
              key={item.title}
              ref={(element) => {
                tabs.current[index] = element;
              }}
              type="button"
              role="tab"
              id={`${id}-tab-${index}`}
              aria-selected={isActive}
              aria-controls={`${id}-panel`}
              tabIndex={isActive ? 0 : -1}
              onClick={() => choose(index)}
              className={cn(
                "relative flex shrink-0 items-center gap-3 overflow-hidden rounded-xl px-3 py-2.5 text-left transition-colors duration-200 ease-(--ease-quart)",
                isActive
                  ? "bg-tint/6 text-fg"
                  : "text-fg-muted hover:bg-tint/4 hover:text-fg",
              )}
            >
              <span
                className={cn(
                  "flex size-6 shrink-0 items-center justify-center rounded-md transition-colors duration-200",
                  isActive
                    ? "bg-violet text-white"
                    : "bg-tint/6 text-fg-subtle",
                )}
              >
                <Icon size={14} aria-hidden="true" />
              </span>
              <span className="whitespace-nowrap font-rounded text-body font-semibold">
                {item.title}
              </span>
              {isActive && isAutoplay && (
                <span
                  key={active}
                  aria-hidden="true"
                  className="feature-progress absolute inset-x-3 bottom-0 h-px origin-left bg-violet-bright"
                  onAnimationEnd={() =>
                    setActive((current) => (current + 1) % features.length)
                  }
                />
              )}
            </button>
          );
        })}
      </div>

      <div
        role="tabpanel"
        id={`${id}-panel`}
        aria-labelledby={`${id}-tab-${active}`}
        className="flex min-w-0 flex-col overflow-hidden rounded-xl bg-canvas"
      >
        <div aria-hidden="true" className="feature-stage aspect-[16/9] w-full">
          <FeatureScene key={active} preview={feature.preview} />
        </div>
        {/* One line from sm up, so switching features never moves the layout. */}
        <div className="flex flex-col gap-2 px-4 pb-3.5 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
          <p className="min-w-0 text-small text-fg-muted sm:truncate">
            {feature.body}
          </p>
          <Link
            href={feature.href}
            className="inline-flex shrink-0 items-center gap-1 text-small font-medium text-violet-bright transition-colors hover:text-fg"
          >
            Read the docs
            <ArrowUpRight size={14} aria-hidden="true" />
          </Link>
        </div>
      </div>
    </div>
  );
}
