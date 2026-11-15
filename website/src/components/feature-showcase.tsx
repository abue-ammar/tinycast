"use client";

import { ArrowUpRight } from "lucide-react";
import Link from "next/link";
import {
  useEffect,
  useId,
  useRef,
  useState,
  type ComponentProps,
  type KeyboardEvent,
} from "react";
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

// Mirrors Tailwind's lg breakpoint, below which the tab list is a horizontal strip.
const carouselQuery = "(width < 64rem)";
const scrollSettleMs = 150;

// The strip renders a clone of the tabs on each side, so it can loop without an edge.
const copies = [-1, 0, 1] as const;

function isCarousel() {
  return window.matchMedia(carouselQuery).matches;
}

function scrollBehavior(): ScrollBehavior {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  return reduce ? "auto" : "smooth";
}

function tabsAt(list: HTMLElement, index: number) {
  return Array.from(
    list.querySelectorAll<HTMLElement>(`[data-feature-index="${index}"]`),
  );
}

function centerOf(list: HTMLElement) {
  return list.scrollLeft + list.clientWidth / 2;
}

function offsetToCenter(list: HTMLElement, tab: HTMLElement) {
  return tab.offsetLeft + tab.offsetWidth / 2 - list.clientWidth / 2;
}

function nearestTab(list: HTMLElement, index: number) {
  const center = centerOf(list);
  const distance = (tab: HTMLElement) =>
    Math.abs(tab.offsetLeft + tab.offsetWidth / 2 - center);
  return tabsAt(list, index).reduce((best, tab) =>
    distance(tab) < distance(best) ? tab : best,
  );
}

// Content is identical in every copy, so shifting by one copy's width is invisible.
function wrapToMiddleCopy(list: HTMLElement) {
  const [before, middle] = tabsAt(list, 0);
  if (!before || !middle) return;
  const span = middle.offsetLeft - before.offsetLeft;
  const center = centerOf(list);
  if (center < middle.offsetLeft) {
    list.scrollTo({ left: list.scrollLeft + span, behavior: "instant" });
  } else if (center >= middle.offsetLeft + span) {
    list.scrollTo({ left: list.scrollLeft - span, behavior: "instant" });
  }
}

// A tab list styled as the palette's own result rows. It advances on its own
// until someone picks a row; from then on the reader is in charge.
export function FeatureShowcase({ features }: { features: Feature[] }) {
  const [active, setActive] = useState(0);
  const [isAutoplay, setIsAutoplay] = useState(true);
  const [isPaused, setIsPaused] = useState(false);
  const [isOffscreen, setIsOffscreen] = useState(true);
  const root = useRef<HTMLDivElement>(null);
  const tablist = useRef<HTMLDivElement>(null);
  const hasCentered = useRef(false);
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

  useEffect(() => {
    const list = tablist.current;
    if (!list || !isCarousel()) return;
    const behavior = hasCentered.current ? scrollBehavior() : "instant";
    const tab = hasCentered.current
      ? nearestTab(list, active)
      : tabsAt(list, active)[1];
    hasCentered.current = true;
    if (!tab) return;
    list.scrollTo({ left: offsetToCenter(list, tab), behavior });
  }, [active]);

  useEffect(() => {
    const list = tablist.current;
    if (!list) return;
    let timer: ReturnType<typeof setTimeout> | undefined;
    function onScroll() {
      clearTimeout(timer);
      timer = setTimeout(() => {
        if (list && isCarousel()) wrapToMiddleCopy(list);
      }, scrollSettleMs);
    }
    list.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      clearTimeout(timer);
      list.removeEventListener("scroll", onScroll);
    };
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
    tabs.current[next]?.focus({ preventScroll: true });
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
        ref={tablist}
        role="tablist"
        aria-label="Features"
        aria-orientation="vertical"
        onKeyDown={onKeyDown}
        className="relative flex gap-1 overflow-x-auto [scrollbar-width:none] lg:flex-col lg:overflow-visible"
      >
        {copies.map((copy) =>
          features.map((item, index) => {
            const isActive = index === active;
            const showsProgress = isActive && isAutoplay;
            if (copy !== 0) {
              return (
                <FeatureTab
                  key={`${copy}-${item.title}`}
                  feature={item}
                  index={index}
                  isActive={isActive}
                  showsProgress={showsProgress}
                  progressKey={active}
                  aria-hidden="true"
                  tabIndex={-1}
                  onClick={() => choose(index)}
                  className="lg:hidden"
                />
              );
            }
            return (
              <FeatureTab
                key={item.title}
                ref={(element) => {
                  tabs.current[index] = element;
                }}
                feature={item}
                index={index}
                isActive={isActive}
                showsProgress={showsProgress}
                progressKey={active}
                onProgressEnd={() =>
                  setActive((current) => (current + 1) % features.length)
                }
                role="tab"
                id={`${id}-tab-${index}`}
                aria-selected={isActive}
                aria-controls={`${id}-panel`}
                tabIndex={isActive ? 0 : -1}
                onClick={() => choose(index)}
              />
            );
          }),
        )}
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

type FeatureTabProps = Omit<ComponentProps<"button">, "children"> & {
  feature: Feature;
  index: number;
  isActive: boolean;
  showsProgress: boolean;
  progressKey: number;
  onProgressEnd?: () => void;
};

function FeatureTab({
  feature,
  index,
  isActive,
  showsProgress,
  progressKey,
  onProgressEnd,
  className,
  ...props
}: FeatureTabProps) {
  const Icon = featureIcons[feature.icon];
  return (
    <button
      type="button"
      data-feature-index={index}
      className={cn(
        "relative flex shrink-0 items-center gap-3 overflow-hidden rounded-xl px-3 py-2.5 text-left transition-colors duration-200 ease-(--ease-quart)",
        isActive
          ? "bg-tint/6 text-fg"
          : "text-fg-muted hover:bg-tint/4 hover:text-fg",
        className,
      )}
      {...props}
    >
      <span
        className={cn(
          "flex size-6 shrink-0 items-center justify-center rounded-md transition-colors duration-200",
          isActive ? "bg-violet text-white" : "bg-tint/6 text-fg-subtle",
        )}
      >
        <Icon size={14} aria-hidden="true" />
      </span>
      <span className="whitespace-nowrap font-rounded text-body font-semibold">
        {feature.title}
      </span>
      {showsProgress && (
        <span
          key={progressKey}
          aria-hidden="true"
          className="feature-progress absolute inset-x-3 bottom-0 h-px origin-left bg-violet-bright"
          onAnimationEnd={onProgressEnd}
        />
      )}
    </button>
  );
}
