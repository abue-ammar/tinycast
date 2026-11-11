"use client";

import { useSidebar } from "fumadocs-ui/components/sidebar/base";
import { useSearchContext } from "fumadocs-ui/contexts/search";
import { PanelLeft, Search } from "lucide-react";
import { iconButtonClass } from "./ui/icon-button";

export function DocsSearchButton() {
  const { enabled, setOpenSearch } = useSearchContext();
  if (!enabled) return null;

  return (
    <button
      type="button"
      onClick={() => setOpenSearch(true)}
      aria-label="Search the docs"
      title="Search the docs"
      className={iconButtonClass}
    >
      <Search size={16} />
    </button>
  );
}

export function DocsSidebarButton() {
  const { open, setOpen } = useSidebar();

  return (
    <button
      type="button"
      onClick={() => setOpen((isOpen) => !isOpen)}
      aria-label={open ? "Close the docs menu" : "Open the docs menu"}
      aria-expanded={open}
      aria-controls="nd-sidebar-mobile"
      className={iconButtonClass}
    >
      <PanelLeft size={16} />
    </button>
  );
}
