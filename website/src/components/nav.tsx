import { BookOpen, Star } from "lucide-react";
import type { ReactNode } from "react";
import { nav, site } from "../data/site";
import { cn } from "../lib/cn";
import { starCount } from "../lib/version";
import { DiscordLogo, GitHubLogo, Logo, SupportIcon } from "./ui/icon";
import { iconButtonClass } from "./ui/icon-button";
import { Link } from "./ui/link";
import { ThemeSwitch } from "./ui/theme-toggle";

// One thin bar on a hairline, see-through over the hero and glass once the page
// scrolls. Phones get icons instead of a menu: the section links are a scroll
// away, and a drawer is one more thing to open.
export function Nav() {
  return (
    <NavFrame
      sections={
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
      }
    >
      <SupportLink />
      <GitHubLink />
      <DiscordLink />
      <Link
        href="/docs"
        aria-label="Documentation"
        className={`${iconButtonClass} md:hidden`}
      >
        <BookOpen size={16} />
      </Link>
      {/* Hidden while the site is dark only. */}
      <ThemeSwitch className="hidden" />
    </NavFrame>
  );
}

// The docs header renders this same frame, so the bar holds still between pages.
export function NavFrame({
  className,
  sections,
  children,
}: {
  className?: string;
  sections?: ReactNode;
  children: ReactNode;
}) {
  return (
    <header
      className={cn(
        "header-veil sticky top-0 z-50 border-b border-border",
        className,
      )}
    >
      <div className="mx-auto flex h-12 max-w-7xl items-center gap-6 px-4 sm:px-10">
        <Link href="/" className="flex items-center gap-2">
          <Logo size={24} />
          <span className="font-rounded text-title font-semibold text-fg">
            {site.name}
          </span>
        </Link>
        {sections}
        <div className="ml-auto flex items-center gap-1">{children}</div>
      </div>
    </header>
  );
}

export function SupportLink() {
  return (
    <Link
      href={site.support}
      aria-label="Support Tinycast"
      title="Support Tinycast"
      className="flex h-8 items-center gap-1.5 rounded-full px-2 text-small text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg sm:px-2.5"
    >
      <SupportIcon size={17} className="text-violet-bright" />
      <span className="hidden sm:inline">Support</span>
    </Link>
  );
}

export async function GitHubLink() {
  const stars = await starCount();

  return (
    <a
      href={site.repo}
      target="_blank"
      rel="noreferrer"
      aria-label={stars ? `${stars} stars on GitHub` : "View source on GitHub"}
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
  );
}

export function DiscordLink() {
  return (
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
  );
}
