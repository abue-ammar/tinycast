"use client";

import { useState } from "react";
import { channels, quarantineCommand, site } from "../data/site";
import { cn } from "../lib/cn";
import { CopyCommand } from "./ui/copy-command";
import { Section } from "./ui/section";

export function Install() {
  const [active, setActive] = useState<string>(channels[0].id);
  const channel = channels.find((c) => c.id === active) ?? channels[0];

  return (
    <Section
      id="install"
      eyebrow="Get it"
      title="Install with Homebrew."
      intro="One command and you're running. Each channel installs as its own app, so a pre-release can live beside stable."
    >
      {/* Full width: a 2xl column scrolled the brew commands sideways. */}
      <div>
        <div className="mb-4 flex items-center justify-between gap-3">
          <div
            className="inline-flex items-center gap-1 rounded-lg bg-tint/5 p-1"
            role="tablist"
            aria-label="Install channel"
          >
            {channels.map((c) => (
              <button
                key={c.id}
                type="button"
                role="tab"
                aria-selected={c.id === active}
                onClick={() => setActive(c.id)}
                className={cn(
                  "rounded-md px-3 py-1.5 text-small font-medium transition-colors",
                  c.id === active
                    ? "bg-action text-action-fg"
                    : "text-fg-muted hover:text-fg",
                )}
              >
                {c.label}
              </button>
            ))}
          </div>
          <span className="rounded-md bg-badge px-2 py-1 font-mono text-caption text-fg-muted">
            {channel.note}
          </span>
        </div>

        <CopyCommand command={channel.command} />

        {/* Homebrew clears the quarantine flag on every install and update, so
            this only ever applies to a hand-downloaded DMG. */}
        <div className="mt-6 rounded-xl border border-border p-4">
          <p className="text-body font-medium text-fg">
            Downloading the DMG instead?
          </p>
          <p className="mt-1.5 text-body text-fg-muted">
            Tinycast is self-signed — there's no paid Developer ID behind it —
            so macOS quarantines a direct download. Homebrew clears that flag
            for you on every install and update. If you grab the DMG from
            Releases by hand, clear it once:
          </p>
          <div className="mt-3">
            <CopyCommand command={quarantineCommand} />
          </div>
        </div>

        <p className="mt-6 text-center text-small text-fg-subtle">
          <a
            href={`${site.repo}/releases`}
            target="_blank"
            rel="noreferrer"
            className="transition-colors hover:text-fg"
          >
            All releases on GitHub →
          </a>
        </p>
      </div>
    </Section>
  );
}
