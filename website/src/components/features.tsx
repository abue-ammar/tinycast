import { ArrowUpRight } from "lucide-react";
import Link from "next/link";
import { coreFeatures, moreFeatures } from "../data/features";
import { FeatureShowcase } from "./feature-showcase";
import { featureIcons } from "./ui/feature-icons";
import { Section } from "./ui/section";

function MoreFeatures() {
  return (
    <div className="mt-16">
      <div className="flex flex-wrap items-baseline justify-between gap-4 border-b border-border pb-4">
        <h3 className="text-title font-semibold text-fg">Also in Tinycast</h3>
        <Link
          href="/docs"
          className="inline-flex items-center gap-1 text-small font-medium text-violet-bright transition-colors hover:text-fg"
        >
          Browse the docs
          <ArrowUpRight size={14} aria-hidden="true" />
        </Link>
      </div>
      <ul className="grid gap-x-8 sm:grid-cols-2 lg:grid-cols-3">
        {moreFeatures.map(({ icon, title, href }) => {
          const Icon = featureIcons[icon];
          return (
            <li key={title} className="border-b border-border">
              <Link
                href={href}
                className="group flex items-center gap-3 py-3 text-body text-fg-muted transition-colors hover:text-fg"
              >
                <Icon
                  size={16}
                  className="shrink-0 text-fg-subtle transition-colors group-hover:text-violet-bright"
                  aria-hidden="true"
                />
                {title}
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

export function Features() {
  return (
    <Section
      id="features"
      index={1}
      label="Features"
      title="One palette for the things you do all day."
      intro="Most features are off until you turn them on, so Tinycast only runs what you use."
    >
      <FeatureShowcase features={coreFeatures} />
      <MoreFeatures />
    </Section>
  );
}
