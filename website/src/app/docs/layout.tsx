import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { Heart } from "lucide-react";
import type { ReactNode } from "react";
import { DocsProvider } from "../../components/docs-provider";
import { DiscordLogo, GitHubLogo, Logo } from "../../components/ui/icon";
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
        // `type: "icon"` is what places these in the sidebar's bottom bar
        // beside the theme switch. Passing `githubUrl` instead would put
        // GitHub there but leave Discord with nowhere to go.
        links={[
          // A button, not an icon: a 16pt glyph would hide it beside GitHub and Discord.
          {
            type: "button",
            text: (
              <span className="flex items-center gap-1.5">
                <Heart size={15} />
                Support
              </span>
            ),
            url: site.support,
            external: true,
          },
          {
            type: "icon",
            text: "GitHub",
            label: "GitHub repository",
            url: site.repo,
            icon: <GitHubLogo size={16} />,
            external: true,
          },
          {
            type: "icon",
            text: "Discord",
            label: "Join the Discord",
            url: site.community.discord,
            icon: <DiscordLogo size={16} />,
            external: true,
          },
        ]}
        nav={{
          title: (
            <span className="flex items-center gap-1.5 font-semibold text-fg">
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
