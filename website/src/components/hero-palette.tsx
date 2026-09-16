import { FileCode2, Ghost, Link2, Search, Terminal } from "lucide-react";
import type { ComponentType } from "react";
import {
  demoAction,
  demoQuery,
  demoScope,
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

function FilterGlyph() {
  return (
    <svg
      viewBox="0 0 24 24"
      className="size-4"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M3 9h18" />
      <path d="M3 15h10" />
    </svg>
  );
}

function Keycap({ children }: { children: string }) {
  return (
    <span className="inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-[5px] bg-(--glass-chip) px-1 text-caption text-(--glass-fg-muted)">
      {children}
    </span>
  );
}

function ResultRow({ row, isSelected }: { row: DemoRow; isSelected: boolean }) {
  const Icon = rowIcons[row.icon];
  return (
    <li
      className={cn(
        "flex items-center gap-3 rounded-[10px] px-2.5 py-2",
        isSelected && "bg-(--glass-chip)",
      )}
    >
      <span
        className="flex size-7 shrink-0 items-center justify-center rounded-[7px] text-white"
        style={{ background: row.tint }}
      >
        <Icon size={15} />
      </span>
      <span className="min-w-0 flex-1 truncate text-demo-row text-(--glass-fg)">
        {row.title}
      </span>
      <span className="shrink-0 text-demo-row text-(--glass-fg-subtle)">
        {row.kind}
      </span>
    </li>
  );
}

// The palette as the app draws it. No rule anywhere inside: the real window
// separates its search field, list and action bar with spacing alone, and a
// hairline is the one thing that makes a mock read as a web card.
export function HeroPalette() {
  return (
    <div
      aria-hidden="true"
      className="glass-palette w-full rounded-2xl p-2 text-left"
    >
      <span aria-hidden="true" className="glass-grain" />

      <div className="flex items-center gap-3 px-3 py-2">
        <Search size={19} className="shrink-0 text-(--glass-fg-subtle)" />
        <span className="flex min-w-0 flex-1 items-center text-demo-query text-(--glass-fg)">
          <span className="truncate">{demoQuery}</span>
          <span className="demo-caret ml-px h-[1.1em] w-0.5 shrink-0 rounded-full bg-violet-bright" />
        </span>
      </div>

      <div className="pb-1">
        {demoSections.map((section) => (
          <div key={section.title}>
            <p className="px-2.5 pb-1.5 pt-2 text-caption text-(--glass-fg-subtle)">
              {section.title}
            </p>
            <ul className="flex flex-col gap-0.5">
              {section.rows.map((row, rowIndex) => (
                <ResultRow
                  key={row.title}
                  row={row}
                  isSelected={
                    section.title === demoSections[0].title && rowIndex === 0
                  }
                />
              ))}
            </ul>
          </div>
        ))}
      </div>

      <div className="flex items-center justify-between gap-2 pl-1 pr-0.5 pt-4">
        <span className="flex items-center gap-2">
          <span className="flex size-7 items-center justify-center rounded-full bg-(--glass-chip-soft) text-(--glass-fg-muted)">
            <FilterGlyph />
          </span>
          <span className="text-caption text-(--glass-fg-subtle)">
            {demoScope}
          </span>
        </span>
        <span className="flex items-center gap-1 rounded-[10px] bg-(--glass-chip-soft) p-1 text-caption">
          <span className="flex items-center gap-1.5 pl-1.5 font-medium text-(--glass-fg)">
            {demoAction}
            <Keycap>↵</Keycap>
          </span>
          <span className="mx-0.5 h-3.5 w-px bg-(--glass-key-border)" />
          <span className="flex items-center gap-1.5 pl-1.5 font-medium text-(--glass-fg-muted)">
            Actions
            <span className="flex gap-1">
              <Keycap>⌘</Keycap>
              <Keycap>K</Keycap>
            </span>
          </span>
        </span>
      </div>
    </div>
  );
}
