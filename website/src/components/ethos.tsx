import { Check } from "lucide-react";
import { values } from "../data/ethos";
import { stats } from "../data/site";
import { Reveal } from "./ui/reveal";
import { Section } from "./ui/section";

export function Ethos() {
  return (
    <Section
      id="why"
      eyebrow="Why it's tiny"
      title="Built like a Mac app should be."
      intro="Native SwiftUI and AppKit, with zero third-party dependencies. Fast because there's barely anything to it."
    >
      {/* Stat strip — the one place numbers get loud. */}
      <Reveal className="mb-10 md:mb-14">
        <div className="grid grid-cols-3 gap-px overflow-hidden rounded-2xl bg-tint/5 shadow-key">
          {stats.map((stat) => (
            <div
              key={stat.label}
              className="bg-surface px-4 py-6 text-center sm:px-6 sm:py-8"
            >
              <div className="text-stat font-medium text-fg">
                {stat.value}
                {stat.unit && (
                  <span className="ml-1 text-body-lg text-fg-muted">
                    {stat.unit}
                  </span>
                )}
              </div>
              <div className="mt-3 font-mono text-eyebrow uppercase text-fg-subtle">
                {stat.label}
              </div>
            </div>
          ))}
        </div>
      </Reveal>

      <Reveal>
        <ul className="flex flex-wrap justify-center gap-2">
          {values.map((value) => (
            <li
              key={value}
              className="inline-flex items-center gap-1.5 rounded-lg bg-tint/5 px-3 py-2 text-small text-fg-muted shadow-keycap"
            >
              <Check
                size={13}
                strokeWidth={2.4}
                className="text-violet-bright"
              />
              {value}
            </li>
          ))}
        </ul>
      </Reveal>
    </Section>
  );
}
