import { site } from "../data/site";
import { supportHero } from "../data/support";
import { Button } from "./ui/button";
import { GitHubLogo, Logo, SupportIcon } from "./ui/icon";

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
        {supportHero.title}
      </h2>
      <p className="mx-auto mt-4 max-w-lg text-pretty text-body-lg text-fg-muted">
        {supportHero.intro}
      </p>
      <div className="mt-8 flex flex-wrap justify-center gap-3">
        <Button href={site.support} size="lg">
          <SupportIcon size={18} />
          Support Tinycast
        </Button>
        <Button href={site.repo} variant="ghost" size="lg">
          <GitHubLogo size={16} />
          Star on GitHub
        </Button>
      </div>
    </section>
  );
}
