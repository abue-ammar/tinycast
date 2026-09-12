import { Heart } from "lucide-react";
import { site } from "../data/site";
import { DiscordLogo, GitHubLogo, Logo } from "./ui/icon";
import { Link } from "./ui/link";
import { MetaStrip } from "./ui/meta-strip";
import { ThemeToggle } from "./ui/theme-toggle";

export function Footer() {
  const repoPath = site.repo.replace("https://", "");

  return (
    <footer className="border-t border-border/50">
      <div className="container-page relative flex flex-col items-center gap-6 py-14 text-center">
        <Link
          href="/"
          className="flex items-center gap-1 text-body font-medium text-fg"
        >
          <Logo size={24} />
          {site.name}
        </Link>

        <div className="flex flex-col items-center gap-2">
          <MetaStrip />
          <p className="font-mono text-caption text-fg-subtle">
            Made for people who like their Mac fast
          </p>
        </div>

        <div className="flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
          <Link
            href="/docs"
            className="text-small text-fg-muted transition-colors hover:text-fg"
          >
            Documentation
          </Link>
          <a
            href={site.repo}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-2 text-small text-fg-muted transition-colors hover:text-fg"
          >
            <GitHubLogo size={16} />
            {repoPath}
          </a>
          <a
            href={site.community.discord}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-2 text-small text-fg-muted transition-colors hover:text-fg"
          >
            <DiscordLogo size={16} />
            Join the Discord
          </a>
          <a
            href={site.support}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-2 text-small text-fg-muted transition-colors hover:text-fg"
          >
            <Heart size={16} />
            Support Tinycast
          </a>
        </div>

        {/* In flow on mobile, where an absolute one would cover the links. */}
        <div className="md:absolute md:bottom-14 md:right-6">
          <ThemeToggle />
        </div>
      </div>
    </footer>
  );
}
