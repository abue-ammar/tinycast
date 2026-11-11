import { Star } from "lucide-react";
import { site } from "../data/site";
import { starCount } from "../lib/version";
import { GitHubLogo, SupportIcon } from "./ui/icon";
import { Link } from "./ui/link";

const tileClass =
  "flex h-8 items-center justify-center gap-1.5 rounded-lg border border-border text-small text-fg-muted transition-colors hover:border-border-strong hover:bg-tint/5 hover:text-fg";

export async function DocsSidebarLinks() {
  const stars = await starCount();

  return (
    <div className="grid grid-cols-2 gap-2">
      <Link href={site.support} className={tileClass}>
        <SupportIcon size={15} className="text-violet-bright" />
        Support
      </Link>
      <a
        href={site.repo}
        target="_blank"
        rel="noreferrer"
        aria-label={
          stars ? `${stars} stars on GitHub` : "View source on GitHub"
        }
        className={tileClass}
      >
        <GitHubLogo size={15} />
        {stars ? (
          <span className="inline-flex items-center gap-1 font-mono text-caption">
            <Star size={12} aria-hidden="true" />
            {stars}
          </span>
        ) : (
          "GitHub"
        )}
      </a>
    </div>
  );
}
