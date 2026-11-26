"use client";

import { ChevronDown } from "lucide-react";
import { useState, type ReactNode } from "react";
import { cn } from "../lib/cn";

// The wall opens folded so the page stays short. Focus inside unfolds it, so tabbing never lands
// on a card hidden under the fade.
export function TestimonialsFold({
  count,
  children,
}: {
  count: number;
  children: ReactNode;
}) {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <div className="relative">
      {/* The padding gives a tilted card's corners room inside the clip. */}
      <div
        onFocus={() => setIsOpen(true)}
        className={cn(
          "-m-3 p-3",
          !isOpen && "max-h-144 overflow-hidden mask-b-from-35% lg:max-h-160",
        )}
      >
        {children}
      </div>
      {!isOpen && (
        <div className="absolute inset-x-0 bottom-0 flex justify-center">
          <button
            type="button"
            onClick={() => setIsOpen(true)}
            className="inline-flex h-9 items-center gap-2 rounded-full bg-tint/6 px-3.5 text-small font-medium text-fg shadow-line transition-[background-color,box-shadow,scale] duration-200 ease-(--ease-quart) hover:bg-tint/10 hover:shadow-line-hover active:scale-97"
          >
            Show all {count} posts
            <ChevronDown size={14} aria-hidden="true" />
          </button>
        </div>
      )}
    </div>
  );
}
