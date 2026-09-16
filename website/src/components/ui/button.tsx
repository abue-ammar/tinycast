import type { ComponentProps, ReactNode } from "react";
import { cn } from "../../lib/cn";
import { Link } from "./link";

type Variant = "primary" | "action" | "ghost" | "outline";
type Size = "sm" | "md" | "lg";

type ButtonProps = {
  children: ReactNode;
  href: string;
  variant?: Variant;
  size?: Size;
} & Omit<ComponentProps<typeof Link>, "href">;

// Each variant carries its own radius: the pill reads as a web CTA, which is
// wrong for the action surface, and that one is square-ish like the app's own.
const variants: Record<Variant, string> = {
  // The brand violet marks the one action that matters: getting the app.
  primary: "rounded-full bg-violet text-white hover:bg-violet-deep",
  // Ink on Light, paper on Dark — the highest-contrast surface either theme has.
  action: "rounded-md bg-action text-action-fg hover:opacity-90",
  ghost: "rounded-full text-fg-muted hover:bg-tint/5 hover:text-fg",
  outline:
    "rounded-full border border-border text-fg-muted hover:border-border-strong hover:text-fg",
};

const sizes: Record<Size, string> = {
  sm: "h-7 gap-1 px-3.5 text-small",
  md: "h-9 gap-2 px-3.5 text-small",
  lg: "h-11 gap-2 px-6 text-body",
};

// A link styled as a button. Everything on this page is a link (download /
// anchor / repo), so an anchor is the honest element.
export function Button({
  children,
  href,
  variant = "primary",
  size = "sm",
  className,
  ...props
}: ButtonProps) {
  return (
    <Link
      href={href}
      className={cn(
        "inline-flex shrink-0 items-center justify-center whitespace-nowrap font-medium transition-colors active:translate-y-px",
        variants[variant],
        sizes[size],
        className,
      )}
      {...props}
    >
      {children}
    </Link>
  );
}
