import { Heart } from "lucide-react";
import { site } from "../data/site";
import { Button } from "./ui/button";
import { GitHubLogo, Logo } from "./ui/icon";

// The mark alone on a violet glow, so the page ends on the brand.
function GlowingMark() {
  return (
    <span className="relative mx-auto flex size-28 items-center justify-center sm:size-32">
      <span
        aria-hidden="true"
        className="mark-bloom pointer-events-none absolute -inset-32"
      />
      <Logo size={72} className="relative" />
    </span>
  );
}

export function Support() {
  return (
    <section id="support" className="px-4 pb-24 pt-24 text-center sm:px-10 ">
      <div aria-hidden="true">
        <GlowingMark />
      </div>
      <h2 className="mx-auto mt-14 max-w-2xl text-closing">
        Keep Tinycast free.
      </h2>
      <p className="mx-auto mt-4 max-w-lg text-pretty text-body-lg text-fg-muted">
        Tinycast is free and open source, with no account and no telemetry. If
        it has earned a place on your Mac, your support keeps development going.
      </p>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Button href={site.support} size="lg">
          <Heart size={16} />
          Support development
        </Button>
        <Button href={site.repo} variant="ghost" size="lg">
          <GitHubLogo size={16} />
          Star on GitHub
        </Button>
      </div>
    </section>
  );
}
