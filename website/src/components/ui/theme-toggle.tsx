"use client";

import { Monitor, Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";
import { useSyncExternalStore } from "react";
import { cn } from "../../lib/cn";

const noop = () => () => {};

// The server can't know the stored choice, so anything that depends on it has
// to wait for hydration — otherwise it renders the wrong state and flips.
function useHasMounted() {
  return useSyncExternalStore(
    noop,
    () => true,
    () => false,
  );
}

// Three explicit targets, never a cycling button: landing on Light at night blinds the reader.
const options = [
  { value: "light", label: "Light", Icon: Sun },
  { value: "system", label: "System", Icon: Monitor },
  { value: "dark", label: "Dark", Icon: Moon },
] as const;

export function ThemeToggle({ className }: { className?: string }) {
  const { theme, setTheme } = useTheme();
  const mounted = useHasMounted();

  return (
    <div
      className={cn(
        "inline-flex items-center gap-1 rounded-full border border-border p-1",
        className,
      )}
      role="radiogroup"
      aria-label="Appearance"
    >
      {options.map(({ value, label, Icon }) => {
        const active = mounted && theme === value;
        return (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={active}
            aria-label={label}
            title={label}
            onClick={() => setTheme(value)}
            className={cn(
              "flex size-8 items-center justify-center rounded-full transition-colors",
              active
                ? "bg-tint/10 text-fg"
                : "text-fg-subtle hover:bg-tint/5 hover:text-fg",
            )}
          >
            <Icon size={16} strokeWidth={1.9} />
          </button>
        );
      })}
    </div>
  );
}

// The header's one-tap flip between Light and Dark. It is not a replacement for
// the three-way control above: that one still owns System, which a flip cannot
// reach, so the footer keeps it.
export function ThemeSwitch({ className }: { className?: string }) {
  const { resolvedTheme, setTheme } = useTheme();
  const mounted = useHasMounted();
  const isDark = mounted && resolvedTheme === "dark";
  const Icon = isDark ? Sun : Moon;

  return (
    <button
      type="button"
      onClick={() => setTheme(isDark ? "light" : "dark")}
      aria-label={isDark ? "Switch to light" : "Switch to dark"}
      title={isDark ? "Switch to light" : "Switch to dark"}
      className={cn(
        "flex size-8 items-center justify-center rounded-full text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg",
        className,
      )}
    >
      {mounted ? (
        <Icon size={16} strokeWidth={1.9} />
      ) : (
        <span className="size-4" />
      )}
    </button>
  );
}
