"use client";

import { Menu, X } from "lucide-react";
import { useState } from "react";
import { nav, site } from "../data/site";
import { cn } from "../lib/cn";
import { Button } from "./ui/button";
import { AppleLogo, DiscordLogo, GitHubLogo, Logo } from "./ui/icon";
import { Link } from "./ui/link";

export function Nav() {
  const [open, setOpen] = useState(false);
  const close = () => setOpen(false);
  const discord = site.community.discord;

  return (
    <header className="fixed inset-x-0 top-4 z-50">
      <div className="container-page">
        <nav className="rounded-2xl border border-border bg-canvas/60 backdrop-blur-2xl">
          <div className="flex items-center justify-between gap-4 px-4 py-3">
            <Link
              href="/"
              onClick={close}
              className="flex items-center gap-1 pl-1 text-body font-semibold text-fg"
            >
              <Logo size={24} />
              {site.name}
            </Link>

            <div className="hidden items-center gap-1 md:flex">
              {nav.map((item) => (
                <Link
                  key={item.label}
                  href={item.href}
                  className="rounded-md px-3 py-1.5 text-small font-medium text-fg-muted transition-colors hover:text-fg"
                >
                  {item.label}
                </Link>
              ))}
            </div>

            <div className="hidden items-center gap-2 md:flex">
              {/* Moved out of the hero, so its pair stays Download and Support. */}
              <a
                href={site.repo}
                target="_blank"
                rel="noreferrer"
                aria-label="View source on GitHub"
                title="View source on GitHub"
                className="flex size-8 items-center justify-center rounded-md text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg"
              >
                <GitHubLogo size={18} />
              </a>
              <a
                href={discord}
                target="_blank"
                rel="noreferrer"
                aria-label="Join the Discord"
                title="Join the Discord"
                className="flex size-8 items-center justify-center rounded-md text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg"
              >
                <DiscordLogo size={18} />
              </a>
              <Button href="/#install" size="sm" className="gap-1">
                <AppleLogo size={20} />
                Download
              </Button>
            </div>

            <button
              type="button"
              onClick={() => setOpen((o) => !o)}
              aria-expanded={open}
              aria-controls="mobile-nav"
              aria-label={open ? "Close menu" : "Open menu"}
              className="flex size-8 items-center justify-center rounded-md text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg md:hidden"
            >
              <span className="relative size-4.5">
                <Menu
                  size={18}
                  className={cn(
                    "absolute inset-0 transition-all duration-300",
                    open && "rotate-90 opacity-0",
                  )}
                />
                <X
                  size={18}
                  className={cn(
                    "absolute inset-0 transition-all duration-300",
                    !open && "-rotate-90 opacity-0",
                  )}
                />
              </span>
            </button>
          </div>

          {/* Mobile menu, always mounted so the drawer can animate open and closed. */}
          <div
            id="mobile-nav"
            className="nav-drawer md:hidden"
            data-open={open}
            inert={!open}
          >
            <div>
              <div className="border-t border-border p-2">
                {nav.map((item) => (
                  <Link
                    key={item.label}
                    href={item.href}
                    onClick={close}
                    className="block rounded-lg px-3 py-2.5 text-body font-medium text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg"
                  >
                    {item.label}
                  </Link>
                ))}
                <a
                  href={discord}
                  target="_blank"
                  rel="noreferrer"
                  onClick={close}
                  className="flex items-center gap-2 rounded-lg px-3 py-2.5 text-body font-medium text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg"
                >
                  <DiscordLogo size={16} />
                  Join the Discord
                </a>
                <Button
                  href="/#install"
                  size="sm"
                  onClick={close}
                  className="mt-2 w-full"
                >
                  <AppleLogo size={14} />
                  Download
                </Button>
              </div>
            </div>
          </div>
        </nav>
      </div>
    </header>
  );
}
