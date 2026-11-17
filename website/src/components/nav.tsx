import { Star } from "lucide-react";
import type { ReactNode } from "react";
import { nav, site } from "../data/site";
import { cn } from "../lib/cn";
import { starCount } from "../lib/version";
import { DocsSearchButton, DocsSidebarButton } from "./docs-nav-buttons";
import { DocsSidebarLinks } from "./docs-sidebar-links";
import { SiteMenuDrawer, SiteMenuProvider } from "./site-menu";
import { DiscordLogo, GitHubLogo, SupportIcon } from "./ui/icon";
import { iconButtonClass } from "./ui/icon-button";
import { Link } from "./ui/link";
import { SiteBrand } from "./ui/site-brand";
import { ThemeSwitch } from "./ui/theme-toggle";

// One thin bar on a hairline, see-through over the hero and glass once the page
// scrolls. Phones get the docs bar's search and drawer, so both bars match.
export function Nav() {
  return (
    <SiteMenuProvider>
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
        <DiscordLink className="max-md:hidden" />
        <div className="flex items-center md:hidden">
          <DocsSearchButton />
          <DocsSidebarButton />
        </div>
        {/* Hidden while the site is dark only. */}
        <ThemeSwitch className="hidden" />
      </NavFrame>
      {/* Outside the header: its backdrop filter would pin a fixed drawer to the bar. */}
      <SiteMenuDrawer banner={<DocsSidebarLinks />} />
    </SiteMenuProvider>
  );
}

// The docs header renders this same frame, so the bar holds still between pages.
// z-30 keeps it under the search dialog and the menu drawer.
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
        "header-veil sticky top-0 z-30 border-b border-border",
        className,
      )}
    >
      <div className="mx-auto flex h-12 max-w-7xl items-center gap-3 px-4 sm:gap-6 sm:px-10">
        <SiteBrand />
        {sections}
        {/* Pulls the last icon's inner padding out, so the edges match the logo's. */}
        <div className="-mr-2 ml-auto flex items-center md:gap-0.5">
          {children}
        </div>
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
      <SupportIcon size={18} className="text-violet-bright" />
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
          ? "flex h-8 items-center justify-center gap-1 rounded-full px-2 text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg sm:gap-1.5 sm:px-2.5"
          : iconButtonClass
      }
    >
      <GitHubLogo size={18} />
      {stars && (
        <span className="inline-flex items-center gap-1 font-mono text-caption">
          <Star size={12} aria-hidden="true" />
          {stars}
        </span>
      )}
    </a>
  );
}

export function DiscordLink({ className }: { className?: string }) {
  return (
    <a
      href={site.community.discord}
      target="_blank"
      rel="noreferrer"
      aria-label="Join the Discord"
      title="Join the Discord"
      className={cn(iconButtonClass, className)}
    >
      <DiscordLogo size={18} />
    </a>
  );
}
