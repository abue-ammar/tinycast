import { FileCode2, Ghost, Link2, Search, Terminal } from "lucide-react";
import type { ComponentType } from "react";
import {
  demoAction,
  demoQuery,
  demoSections,
  type DemoRow,
  type DemoRowIcon,
} from "../data/demo";
import { cn } from "../lib/cn";
import { GitHubLogo } from "./ui/icon";

const rowIcons: Record<DemoRowIcon, ComponentType<{ size?: number }>> = {
  ghost: Ghost,
  github: GitHubLogo,
  link: Link2,
  file: FileCode2,
  terminal: Terminal,
};

function Keycap({ children }: { children: string }) {
  return (
    <span className="inline-flex h-5 min-w-5 items-center justify-center rounded-md bg-(--glass-chip) px-1 text-caption text-(--glass-fg-muted)">
      {children}
    </span>
  );
}

function ResultRow({ row, isSelected }: { row: DemoRow; isSelected: boolean }) {
  const Icon = rowIcons[row.icon];
  return (
    <li
      className={cn(
        "flex items-center gap-3 rounded-xl px-2.5 py-2",
        isSelected && "glass-chip",
      )}
    >
      <span
        className="flex size-6 shrink-0 items-center justify-center rounded-lg text-white"
        style={{ background: row.tint }}
      >
        <Icon size={13} />
      </span>
      <span className="min-w-0 flex-1 truncate text-demo-row font-medium text-(--glass-fg)">
        {row.title}
      </span>
      <span className="shrink-0 text-demo-row text-(--glass-fg-subtle)">
        {row.kind}
      </span>
    </li>
  );
}

// The palette as the app draws it, sized by its own rows. Height follows the
// content on purpose: a fixed one leaves empty frosted glass under short lists.
export function HeroPalette() {
  return (
    <div
      aria-hidden="true"
      className="glass-palette w-full rounded-[1.75rem] text-left"
    >
      <span aria-hidden="true" className="glass-grain" />

      <div className="flex items-center gap-3 border-b border-(--glass-key-border) px-4 py-3.5">
        <Search size={20} className="shrink-0 text-(--glass-fg-subtle)" />
        <span className="flex min-w-0 flex-1 items-center text-demo-query text-(--glass-fg)">
          <span className="truncate">{demoQuery}</span>
          <span className="demo-caret ml-px h-[1.1em] w-0.5 shrink-0 rounded-full bg-violet-bright" />
        </span>
      </div>

      <div className="px-2 py-2">
        {demoSections.map((section, sectionIndex) => (
          <div key={section.title}>
            <p
              className={cn(
                "px-2.5 pb-1 pt-2 text-caption font-semibold text-(--glass-fg-subtle)",
                sectionIndex === 0 && "pt-1",
              )}
            >
              {section.title}
            </p>
            <ul className="flex flex-col gap-0.5">
              {section.rows.map((row, rowIndex) => (
                <ResultRow
                  key={row.title}
                  row={row}
                  isSelected={sectionIndex === 0 && rowIndex === 0}
                />
              ))}
            </ul>
          </div>
        ))}
      </div>

      <div className="flex items-center justify-between gap-2 border-t border-(--glass-key-border) px-3 py-2">
        <span className="flex size-6 items-center justify-center rounded-full bg-(--glass-chip) text-caption tracking-[0.1em] text-(--glass-fg-muted)">
          •••
        </span>
        <span className="flex items-center gap-2 rounded-lg bg-(--glass-chip-soft) px-1.5 py-1 text-caption">
          <span className="flex items-center gap-1.5 px-1 font-medium text-(--glass-fg)">
            {demoAction}
            <Keycap>↵</Keycap>
          </span>
          <span className="h-3.5 w-px bg-(--glass-key-border)" />
          <span className="flex items-center gap-1.5 px-1 font-medium text-(--glass-fg-muted)">
            Actions
            <Keycap>⌘</Keycap>
            <Keycap>K</Keycap>
          </span>
        </span>
      </div>
    </div>
  );
}
