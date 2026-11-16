"use client";

import {
  SidebarDrawerContent,
  SidebarDrawerOverlay,
  SidebarProvider,
  useSidebar,
} from "fumadocs-ui/components/sidebar/base";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { nav } from "../data/site";
import { DocsProvider } from "./docs-provider";
import { Link } from "./ui/link";

// Fumadocs' docs drawer only renders inside its docs layout, so its classes are restated here
// to make the site's phone menu the same drawer.
const drawerOverlayClass =
  "fixed inset-0 z-40 backdrop-blur-xs data-[state=open]:animate-fd-fade-in data-[state=closed]:animate-fd-fade-out";
const drawerClass =
  "fixed inset-y-0 inset-e-0 z-40 flex w-[85%] max-w-[380px] flex-col border-s bg-fd-background text-[0.9375rem] shadow-lg data-[state=open]:animate-fd-sidebar-in data-[state=closed]:animate-fd-sidebar-out";
const itemClass =
  "relative flex flex-row items-center gap-2 rounded-lg p-2 text-start text-fd-muted-foreground transition-colors hover:bg-fd-accent/50 hover:text-fd-accent-foreground/80 hover:transition-none data-[active=true]:bg-fd-primary/10 data-[active=true]:text-fd-primary";

function withoutTrailingSlash(path: string) {
  return path.length > 1 ? path.replace(/\/$/, "") : path;
}

// The provider closes the drawer when the path changes, which an anchor on this page never does.
function isSamePageAnchor(href: string, pathname: string) {
  const [path, hash] = href.split("#");
  return hash !== undefined && (path || "/") === pathname;
}

// Search and the drawer state live in Fumadocs' providers, the same ones the docs layout mounts.
export function SiteMenuProvider({ children }: { children: ReactNode }) {
  return (
    <DocsProvider>
      <SidebarProvider>{children}</SidebarProvider>
    </DocsProvider>
  );
}

export function SiteMenuDrawer({ banner }: { banner: ReactNode }) {
  const pathname = withoutTrailingSlash(usePathname());
  const { setOpen } = useSidebar();
  const close = () => setOpen(false);

  return (
    <>
      <SidebarDrawerOverlay className={drawerOverlayClass} />
      <SidebarDrawerContent aria-label="Menu" className={drawerClass}>
        <div className="flex flex-col gap-3 p-4 pb-2">{banner}</div>
        <nav aria-label="Sections" className="flex flex-col gap-0.5 p-4">
          {nav.map((item) => (
            <Link
              key={item.label}
              href={item.href}
              data-active={item.href === pathname}
              onClick={
                isSamePageAnchor(item.href, pathname) ? close : undefined
              }
              className={itemClass}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </SidebarDrawerContent>
    </>
  );
}
