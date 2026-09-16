import { BookOpen, Star } from "lucide-react";
import { nav, site } from "../data/site";
import { starCount } from "../lib/version";
import { DiscordLogo, GitHubLogo, Logo } from "./ui/icon";
import { Link } from "./ui/link";
import { ThemeSwitch } from "./ui/theme-toggle";

const iconButtonClass =
  "flex size-8 items-center justify-center rounded-full text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg";

// One thin bar on a hairline, see-through over the hero and glass once the page
// scrolls. Phones get icons instead of a menu: the section links are a scroll
// away, and a drawer is one more thing to open.
export async function Nav() {
  const stars = await starCount();

  return (
    <header className="header-veil sticky top-0 z-50 border-b border-border">
      <div className="mx-auto flex h-12 max-w-7xl items-center gap-6 px-4 sm:px-10">
        <Link href="/" className="flex items-center gap-2">
          <Logo size={24} />
          <span className="text-body font-semibold tracking-[-0.02em] text-fg">
            {site.name}
          </span>
        </Link>

        <nav
          aria-label="Sections"
          className="hidden items-center gap-5 md:flex"
        >
          {nav.map((item) => (
            <Link
              key={item.label}
              href={item.href}
              className="text-small text-fg-muted transition-colors hover:text-fg"
            >
              {item.label}
            </Link>
          ))}
        </nav>

        <div className="ml-auto flex items-center gap-1">
          <Link
            href="/docs"
            aria-label="Documentation"
            className={`${iconButtonClass} md:hidden`}
          >
            <BookOpen size={16} />
          </Link>
          <a
            href={site.repo}
            target="_blank"
            rel="noreferrer"
            aria-label={
              stars ? `${stars} stars on GitHub` : "View source on GitHub"
            }
            title="View source on GitHub"
            className={
              stars
                ? "flex h-8 items-center gap-1.5 rounded-full px-2.5 text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg"
                : iconButtonClass
            }
          >
            <GitHubLogo size={16} />
            {stars && (
              <span className="inline-flex items-center gap-1 font-mono text-caption">
                <Star size={12} aria-hidden="true" />
                {stars}
              </span>
            )}
          </a>
          <a
            href={site.community.discord}
            target="_blank"
            rel="noreferrer"
            aria-label="Join the Discord"
            title="Join the Discord"
            className={iconButtonClass}
          >
            <DiscordLogo size={16} />
          </a>
          <ThemeSwitch />
        </div>
      </div>
    </header>
  );
}
