import { DocsLayout } from "fumadocs-ui/layouts/docs";
import type { ReactNode } from "react";
import { DocsProvider } from "../../components/docs-provider";
import { DocsSidebarLinks } from "../../components/docs-sidebar-links";
import {
  DocsSearchButton,
  DocsSidebarButton,
} from "../../components/docs-nav-buttons";
import {
  ChangelogLink,
  DocsLink,
  GitHubLink,
  NavFrame,
  SupportLink,
} from "../../components/nav";
import { Logo } from "../../components/ui/icon";
import { site } from "../../data/site";
import { source } from "../../lib/source";

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <DocsProvider>
      <DocsLayout
        tree={source.pageTree}
        // The grid centres itself inside `--fd-layout-width`, which on a wide
        // screen leaves a dead margin to the left of the sidebar. Full width
        // collapses that margin so the sidebar sits against the edge.
        containerProps={{ style: { "--fd-layout-width": "100%" } as never }}
        sidebar={{ banner: <DocsSidebarLinks /> }}
        themeSwitch={{ enabled: false }}
        nav={{
          // Our own bar on phones, laid out like the site nav so nothing moves
          // between pages.
          component: (
            <NavFrame className="[grid-area:header] md:hidden">
              <SupportLink />
              <GitHubLink />
              <DocsLink />
              <ChangelogLink />
              <DocsSearchButton />
              <DocsSidebarButton />
            </NavFrame>
          ),
          title: (
            <span className="flex items-center gap-1.5 font-rounded text-title font-semibold text-fg">
              <Logo size={22} />
              {site.name}
            </span>
          ),
        }}
      >
        {children}
      </DocsLayout>
    </DocsProvider>
  );
}
