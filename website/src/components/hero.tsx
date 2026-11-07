import { ArrowRight, ArrowUpRight, Download } from "lucide-react";
import { brewInstallCommand, hero, site } from "../data/site";
import { latestVersion } from "../lib/version";
import { Badges } from "./badges";
import { HeroPalette } from "./hero-palette";
import { Button } from "./ui/button";
import { CommandLine } from "./ui/command-line";
import { Link } from "./ui/link";
import { SwapWords } from "./ui/swap-words";

export async function Hero() {
  const version = await latestVersion();

  return (
    <section id="top" className="relative overflow-hidden">
      <div
        aria-hidden="true"
        className="bg-grid pointer-events-none absolute inset-0"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -top-40 right-[-10%] h-130 w-180 rounded-full opacity-35 blur-3xl"
        style={{
          background:
            "radial-gradient(closest-side, color-mix(in srgb, var(--color-violet) 55%, transparent), transparent)",
        }}
      />

      <div className="relative mx-auto grid max-w-7xl items-center gap-12 px-4 pb-20 pt-14 sm:px-10 lg:grid-cols-[1.15fr_1fr] lg:pb-28 lg:pt-20">
        <div className="min-w-0">
          <p className="blur-in inline-flex items-center gap-2 rounded-full border border-border bg-surface px-3 py-1 font-mono text-micro uppercase text-fg-muted">
            <span
              aria-hidden="true"
              className="size-1.5 rounded-full bg-violet"
            />
            {version} · {site.platform} · Apple silicon
          </p>

          <h1
            className="blur-in @container mt-6 text-display"
            style={{ animationDelay: "60ms" }}
          >
            <span className="sr-only">
              {`${hero.headline.swap[0]} ${hero.headline.rest} ${hero.headline.second}`}
            </span>
            {/* 10.6em fits the widest swap plus the rest, so no swap can ever rewrap the line. */}
            <span
              aria-hidden="true"
              className="block @min-[10.6em]:whitespace-nowrap"
            >
              <SwapWords words={hero.headline.swap} />
              <span className="@max-[10.6em]:block"> {hero.headline.rest}</span>
            </span>
            <span aria-hidden="true" className="block">
              {hero.headline.second}
              <span className="text-violet">_</span>
            </span>
          </h1>

          <p
            className="blur-in mt-6 max-w-lg text-pretty text-body-lg text-fg-muted sm:text-subheading"
            style={{ animationDelay: "120ms" }}
          >
            {hero.sub}
          </p>

          <div
            className="blur-in mt-8 max-w-xl space-y-2"
            style={{ animationDelay: "180ms" }}
          >
            <CommandLine command={brewInstallCommand} />
            <a
              href={site.intelTap}
              target="_blank"
              rel="noreferrer"
              className="flex w-fit items-center gap-1 pl-1 text-small text-fg-subtle transition-colors hover:text-fg"
            >
              Intel Mac? Install from our Homebrew tap
              <ArrowUpRight size={13} aria-hidden="true" />
            </a>
          </div>

          <div
            className="blur-in mt-6 flex flex-wrap items-center gap-3"
            style={{ animationDelay: "240ms" }}
          >
            <Button
              href={`${site.repo}/releases/latest`}
              variant="action"
              size="md"
            >
              <Download size={15} />
              Download for Mac
            </Button>
            <Link
              href="/#gallery"
              className="inline-flex items-center gap-1.5 text-small text-fg-muted transition-colors hover:text-fg"
            >
              See it in action
              <ArrowRight size={14} />
            </Link>
          </div>

          <ul
            className="blur-in mt-8 flex flex-wrap gap-x-5 gap-y-2 font-mono text-micro uppercase text-fg-subtle"
            style={{ animationDelay: "300ms" }}
          >
            {hero.facts.map((fact) => (
              <li key={fact}>{fact}</li>
            ))}
          </ul>

          <div className="blur-in mt-8" style={{ animationDelay: "360ms" }}>
            <Badges />
          </div>
        </div>

        {/* Tilted, never floating: the palette is a backdrop-filter surface, and
            animating its transform repaints the blur on every frame. */}
        <div
          className="rise min-w-0 lg:-rotate-1"
          style={{ animationDelay: "120ms" }}
        >
          <HeroPalette />
        </div>
      </div>
    </section>
  );
}
