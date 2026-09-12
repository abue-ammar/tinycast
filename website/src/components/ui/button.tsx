import type { ComponentProps, ReactNode } from "react";
import { cn } from "../../lib/cn";
import { Link } from "./link";

type Variant = "solid" | "ghost";
type Size = "sm" | "md" | "lg";

type ButtonProps = {
  children: ReactNode;
  href: string;
  variant?: Variant;
  size?: Size;
} & Omit<ComponentProps<typeof Link>, "href">;

const variants: Record<Variant, string> = {
  // The only filled action in the system — neutral, never chromatic.
  solid:
    "bg-action text-action-fg shadow-cta hover:opacity-90 active:translate-y-px",
  // Edge-defined ghost: hairline border, fills only on hover.
  ghost:
    "text-fg-muted border border-border hover:text-fg hover:border-border-strong hover:bg-tint/5",
};

const sizes: Record<Size, string> = {
  sm: "px-3 py-1.5",
  md: "px-4 py-2.5",
  // Hero only. A CTA carrying the page shouldn't wear the nav's 13px type.
  lg: "px-5 py-3 text-body",
};

// A link styled as a button. Everything on this page is a link (download /
// anchor / repo), so an anchor is the honest element.
export function Button({
  children,
  href,
  variant = "solid",
  size = "md",
  className,
  ...props
}: ButtonProps) {
  return (
    <Link
      href={href}
      className={cn(
        "inline-flex items-center justify-center gap-2 rounded-lg text-small font-medium transition-all duration-150",
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
