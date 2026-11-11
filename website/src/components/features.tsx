import { ArrowUpRight } from "lucide-react";
import Link from "next/link";
import { coreFeatures, moreFeatures, type Feature } from "../data/features";
import { cn } from "../lib/cn";
import { FeaturePreviewArt } from "./feature-previews";
import { Button } from "./ui/button";
import { featureIcons } from "./ui/feature-icons";
import { Section } from "./ui/section";

function FeatureCard({ title, body, href, preview, isWide }: Feature) {
  return (
    <Link
      href={href}
      className={cn(
        "group flex min-w-0 flex-col rounded-2xl bg-tint/4 p-2 transition-colors hover:bg-tint/6",
        isWide && "sm:col-span-2",
      )}
    >
      {/* Decorative: the title and body below say the same thing in words. */}
      <div
        aria-hidden="true"
        className="h-44 overflow-hidden rounded-xl bg-canvas p-4"
      >
        <FeaturePreviewArt preview={preview} />
      </div>
      <div className="px-3 pb-3 pt-4">
        <h3 className="flex items-center gap-1 text-title font-semibold text-fg">
          {title}
          <ArrowUpRight
            size={15}
            aria-hidden="true"
            className="text-fg-subtle opacity-0 transition-opacity group-hover:opacity-100"
          />
        </h3>
        <p className="mt-1 text-small text-fg-muted">{body}</p>
      </div>
    </Link>
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
      <div className="grid grid-cols-[minmax(0,1fr)] gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {coreFeatures.map((feature) => (
          <FeatureCard key={feature.title} {...feature} />
        ))}
      </div>

      <div className="mt-4 rounded-2xl bg-tint/4 p-5 sm:p-6">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <h3 className="text-title font-semibold text-fg">Also included</h3>
          <Button href="/docs" variant="outline">
            Browse the docs
          </Button>
        </div>
        <ul className="mt-4 flex flex-wrap gap-2">
          {moreFeatures.map(({ icon, title, href }) => {
            const Icon = featureIcons[icon];
            return (
              <li key={title}>
                <Link
                  href={href}
                  className="inline-flex items-center gap-1.5 rounded-full bg-canvas px-3 py-1.5 text-small text-fg-muted transition-colors hover:text-fg"
                >
                  <Icon
                    size={13}
                    strokeWidth={2}
                    className="text-violet-bright"
                    aria-hidden="true"
                  />
                  {title}
                </Link>
              </li>
            );
          })}
        </ul>
      </div>
    </Section>
  );
}
