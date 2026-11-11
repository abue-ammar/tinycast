import { Cpu, Heart, Lock, ShieldCheck } from "lucide-react";
import type { ComponentType } from "react";
import { ethos, ethosPillars, type EthosPillar } from "../data/ethos";
import { reveal } from "../lib/reveal";
import { RevealWords } from "./ui/reveal-words";

const pillarIcons: Record<
  EthosPillar["icon"],
  ComponentType<{ size?: number; className?: string }>
> = {
  native: Cpu,
  local: Lock,
  source: ShieldCheck,
  free: Heart,
};

// The page's closing statement, as a band that reaches the window edges. It is
// the only place the serif appears, which is what makes it read as a statement
// rather than one more section.
export function Ethos() {
  return (
    <section id="ethos" className="border-y border-border bg-tint/2">
      <div className="mx-auto max-w-7xl px-4 py-20 sm:px-10">
        <blockquote className="mx-auto max-w-3xl text-center">
          <p
            className="text-quote text-balance font-serif text-fg"
            {...reveal("words")}
          >
            <RevealWords text={`“${ethos.quote}`} />{" "}
            <em className="italic text-violet">
              <RevealWords
                text={`${ethos.emphasis}”`}
                start={ethos.quote.split(" ").length}
              />
            </em>
          </p>
          <footer
            className="mt-4 text-small text-fg-subtle"
            {...reveal("text", 4)}
          >
            {ethos.attribution}
          </footer>
        </blockquote>

        <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {ethosPillars.map((pillar, index) => {
            const Icon = pillarIcons[pillar.icon];
            return (
              <div key={pillar.title} {...reveal("text", index)}>
                <Icon size={18} className="text-fg-subtle" />
                <h3 className="mt-3 text-title font-semibold text-fg">
                  {pillar.title}
                </h3>
                <p className="mt-1.5 text-small text-fg-muted">{pillar.body}</p>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
