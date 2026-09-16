import type { ReactNode } from "react";

type SectionProps = {
  id: string;
  /** Position on the page, shown as "01". Sections are read top to bottom. */
  index: number;
  label: string;
  title: ReactNode;
  intro?: ReactNode;
  children: ReactNode;
};

export function SectionLabel({
  index,
  label,
}: {
  index: number;
  label: string;
}) {
  return (
    <p className="flex items-baseline gap-2.5 font-mono text-eyebrow uppercase">
      <span className="text-violet-bright">
        {String(index).padStart(2, "0")}
      </span>
      <span className="text-fg-muted">{label}</span>
    </p>
  );
}

export function Section({
  id,
  index,
  label,
  title,
  intro,
  children,
}: SectionProps) {
  const header = (
    <div className="max-w-2xl">
      <SectionLabel index={index} label={label} />
      <h2 className="mt-4 text-heading">{title}</h2>
      {intro && (
        <p className="mt-4 max-w-xl text-pretty text-body-lg text-fg-muted">
          {intro}
        </p>
      )}
    </div>
  );

  return (
    <section id={id} className="relative">
      <div className="px-4 py-20 sm:px-10 sm:py-24">
        {header}
        <div className="mt-12">{children}</div>
      </div>
    </section>
  );
}
