import { ArrowRight, Download } from "lucide-react";
import { brewInstallCommand, brewTrustCommand, hero, site } from "../data/site";
import { latestVersion } from "../lib/version";
import { HeroPalette } from "./hero-palette";
import { Button } from "./ui/button";
import { CommandLine } from "./ui/command-line";
import { Link } from "./ui/link";

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
        className="pointer-events-none absolute -top-40 right-[-10%] h-[520px] w-[720px] rounded-full opacity-35 blur-3xl"
        style={{
          background:
            "radial-gradient(closest-side, color-mix(in srgb, var(--color-violet) 55%, transparent), transparent)",
        }}
      />

      <div className="relative mx-auto grid max-w-7xl items-center gap-12 px-5 pb-20 pt-14 sm:px-10 lg:grid-cols-[1.15fr_1fr] lg:pb-28 lg:pt-20">
        <div className="min-w-0">
          <p className="rise inline-flex items-center gap-2 rounded-full border border-border bg-surface px-3 py-1 font-mono text-micro uppercase text-fg-muted">
            <span
              aria-hidden="true"
              className="size-1.5 rounded-full bg-violet"
            />
            {version} · {site.platform} · Apple silicon &amp; Intel
          </p>

          <h1
            className="rise mt-6 text-display"
            style={{ animationDelay: "60ms" }}
          >
            {hero.headlineLines.map((line, index) => (
              <span key={line} className="block">
                {line}
                {index === hero.headlineLines.length - 1 && (
                  <span aria-hidden="true" className="text-violet">
                    _
                  </span>
                )}
              </span>
            ))}
          </h1>

          <p
            className="rise mt-6 max-w-lg text-pretty text-body-lg text-fg-muted sm:text-subheading"
            style={{ animationDelay: "120ms" }}
          >
            {hero.sub}
          </p>

          <div
            className="rise mt-8 max-w-lg space-y-2"
            style={{ animationDelay: "180ms" }}
          >
            <CommandLine command={brewTrustCommand} />
            <CommandLine command={brewInstallCommand} />
          </div>

          <div
            className="rise mt-6 flex flex-wrap items-center gap-3"
            style={{ animationDelay: "240ms" }}
          >
            <Button href="/docs/install" variant="action" size="md">
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
            className="rise mt-8 flex flex-wrap gap-x-5 gap-y-2 font-mono text-micro uppercase text-fg-subtle"
            style={{ animationDelay: "300ms" }}
          >
            {hero.facts.map((fact) => (
              <li key={fact}>{fact}</li>
            ))}
          </ul>
        </div>

        {/* Tilted, never floating: the palette is a backdrop-filter surface, and
            animating its transform repaints the blur on every frame. */}
        <div
          className="rise min-w-0 lg:rotate-[-1deg]"
          style={{ animationDelay: "120ms" }}
        >
          <HeroPalette />
        </div>
      </div>
    </section>
  );
}
