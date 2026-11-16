import { site } from "../data/site";
import { supportHero } from "../data/support";
import { reveal } from "../lib/reveal";
import { Button } from "./ui/button";
import { GitHubLogo, Logo, SupportIcon } from "./ui/icon";

export function Support() {
  return (
    <section
      id="support"
      className="flex flex-col items-center px-4 py-16 text-center sm:px-10 sm:py-20"
      {...reveal("content")}
    >
      <Logo size={40} />
      <h2 className="mt-5 font-rounded text-heading text-fg">
        {supportHero.title}
      </h2>
      <p className="mt-3 max-w-xl text-pretty text-small text-fg-muted">
        {supportHero.intro}
      </p>
      <div className="mt-6 flex flex-wrap justify-center gap-2">
        <Button href={site.support} size="md">
          <SupportIcon size={16} />
          Support Tinycast
        </Button>
        <Button href={site.repo} variant="outline" size="md">
          <GitHubLogo size={15} />
          Star on GitHub
        </Button>
      </div>
    </section>
  );
}
