import { site } from "../data/site";
import { latestVersion } from "../lib/version";
import { Logo } from "./ui/icon";
import { Link } from "./ui/link";

const links = [
  { label: "Docs", href: "/docs" },
  { label: "Privacy", href: "/#privacy" },
  { label: "Install", href: "/docs/install" },
  { label: "GitHub", href: site.repo },
  { label: "Discord", href: site.community.discord },
  { label: "Support", href: site.support },
];

// One rule and one row. Everything a three-column sitemap held is a scroll or a
// nav click away on a page this short, and the height it cost was the price.
export async function Footer() {
  const version = await latestVersion();

  return (
    <footer className="border-t border-border">
      <div className="mx-auto flex max-w-7xl flex-col-reverse gap-4 px-4 py-8 sm:px-10 md:flex-row md:items-center md:justify-between">
        <div className="flex items-center gap-2.5">
          <Logo size={20} />
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
        </div>

        <nav
          aria-label="Footer"
          className="flex flex-wrap items-center gap-x-5 gap-y-2"
        >
          {links.map((link) => (
            <Link
              key={link.label}
              href={link.href}
              className="text-small text-fg-muted transition-colors hover:text-fg"
            >
              {link.label}
            </Link>
          ))}
        </nav>
      </div>
    </footer>
  );
}
