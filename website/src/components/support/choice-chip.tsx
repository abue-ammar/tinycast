import type { ReactNode } from "react";
import { cn } from "../../lib/cn";

type Props = {
  name: string;
  value: string;
  checked: boolean;
  onChange: () => void;
  children: ReactNode;
};

// A pill radio. A leading mark pulls the left padding in so it sits snug in the curve.
export function ChoiceChip({
  name,
  value,
  checked,
  onChange,
  children,
}: Props) {
  return (
    <label
      className={cn(
        "flex h-9 cursor-pointer items-center gap-1.5 rounded-lg px-3 text-small font-medium transition-[box-shadow,color,background-color] has-[img]:pl-1.5 has-[img]:pr-3",
        "has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-violet-bright",
        checked
          ? "bg-violet/12 text-fg shadow-[inset_0_0_0_1.5px_var(--color-violet)]"
          : "text-fg-muted shadow-line hover:text-fg hover:shadow-line-hover",
      )}
    >
      <input
        type="radio"
        name={name}
        value={value}
        checked={checked}
        onChange={onChange}
        className="sr-only"
      />
      {children}
    </label>
  );
}
