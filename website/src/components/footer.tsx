import { site } from "../data/site";
import { latestVersion } from "../lib/version";
import { Logo } from "./ui/icon";
import { Link } from "./ui/link";
import { ThemeToggle } from "./ui/theme-toggle";

type FooterLink = { label: string; href: string };

const linkGroups: { title: string; links: FooterLink[] }[] = [
  {
    title: "Product",
    links: [
      { label: "Features", href: "/#features" },
      { label: "Privacy", href: "/#privacy" },
      { label: "Install", href: "/#install" },
    ],
  },
  {
    title: "Resources",
    links: [
      { label: "Documentation", href: "/docs" },
      {
        label: "Import from Raycast",
        href: "/docs/reference/import-from-raycast",
      },
      { label: "Releases", href: `${site.repo}/releases` },
    ],
  },
  {
    title: "Community",
    links: [
      { label: "GitHub", href: site.repo },
      { label: "Discord", href: site.community.discord },
      { label: "Support Tinycast", href: site.support },
    ],
  },
];

export async function Footer() {
  const version = await latestVersion();

  return (
    <footer className="mx-auto max-w-7xl px-5 pb-10 pt-6 sm:px-10">
      <div className="flex flex-col gap-10 md:flex-row md:justify-between">
        <div>
          <Link href="/" className="flex items-center gap-2">
            <Logo size={26} />
            <span className="text-body font-semibold tracking-tight text-fg">
              {site.name}
            </span>
          </Link>
          <p className="mt-3 max-w-xs text-small text-fg-muted">
            {site.tagline}
          </p>
        </div>

        <nav
          aria-label="Footer"
          className="grid grid-cols-2 gap-8 sm:grid-cols-3 sm:gap-16"
        >
          {linkGroups.map((group) => (
            <div key={group.title}>
              <p className="text-small font-medium text-fg">{group.title}</p>
              <ul className="mt-3 flex flex-col gap-2">
                {group.links.map((link) => (
                  <li key={link.label}>
                    <Link
                      href={link.href}
                      className="text-small text-fg-muted transition-colors hover:text-fg"
                    >
                      {link.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </nav>
      </div>

      <div className="mt-14 flex flex-col-reverse items-start gap-4 sm:flex-row sm:items-center sm:justify-between">
        <p className="text-caption text-fg-subtle">
          © {new Date().getFullYear()} {site.name} · {version} ·{" "}
          <a
            href={site.licenseUrl}
            target="_blank"
            rel="noreferrer"
            className="transition-colors hover:text-fg"
          >
            {site.license}
          </a>
        </p>
        <ThemeToggle />
      </div>
    </footer>
  );
}
