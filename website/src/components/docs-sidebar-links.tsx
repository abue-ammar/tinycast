import { SidebarTrigger } from "fumadocs-ui/components/sidebar/base";
import { PanelLeft, Star } from "lucide-react";
import { site } from "../data/site";
import { cn } from "../lib/cn";
import { starCount } from "../lib/version";
import { DiscordLogo, GitHubLogo, SupportIcon } from "./ui/icon";
import { iconButtonClass } from "./ui/icon-button";
import { Link } from "./ui/link";
import { SiteBrand } from "./ui/site-brand";

const tileClass =
  "flex h-8 items-center justify-center gap-1.5 rounded-lg text-small text-fg-muted shadow-line transition-[color,background-color,box-shadow] hover:bg-tint/5 hover:text-fg hover:shadow-line-hover";

export async function DocsSidebarLinks() {
  const stars = await starCount();

  return (
    <div className="-mb-2 flex flex-col gap-4">
      <DrawerHeader />
      <div className="grid grid-cols-[1fr_1fr_auto] gap-2">
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
        <a
          href={site.community.discord}
          target="_blank"
          rel="noreferrer"
          aria-label="Join the Discord"
          className={cn(tileClass, "w-8")}
        >
          <DiscordLogo size={16} />
        </a>
      </div>
    </div>
  );
}

// The phone drawer's header restates the nav bar, so the logo and toggle hold still on open.
// It cancels the drawer's 16px padding to sit flush; the desktop sidebar has its own title.
function DrawerHeader() {
  return (
    <div className="-mx-4 -mt-4 flex h-12 items-center justify-between border-b border-border px-4 md:hidden">
      <SiteBrand />
      <SidebarTrigger
        aria-label="Close the menu"
        className={cn(iconButtonClass, "-mr-2")}
      >
        <PanelLeft size={16} />
      </SidebarTrigger>
    </div>
  );
}
