import type { ReactNode } from "react";
import { reveal } from "../../lib/reveal";
import { RevealWords } from "./reveal-words";

type SectionProps = {
  id: string;
  label: string;
  title: string;
  intro?: ReactNode;
  children: ReactNode;
};

export function Section({ id, label, title, intro, children }: SectionProps) {
  const header = (
    <div className="max-w-2xl">
      <p
        className="text-label font-medium text-violet-bright"
        {...reveal("text")}
      >
        {label}
      </p>
      <h2
        className="mt-3 text-balance text-heading text-fg"
        {...reveal("words", 1)}
      >
        <RevealWords text={title} />
      </h2>
      {intro && (
        <p
          className="mt-4 max-w-xl text-pretty text-body-lg text-fg-muted"
          {...reveal("text", 2)}
        >
          {intro}
        </p>
      )}
    </div>
  );

  return (
    <section id={id} className="relative">
      <div className="px-4 py-20 sm:px-10 sm:py-24">
        {header}
        <div className="mt-12" {...reveal("content", 3)}>
          {children}
        </div>
      </div>
    </section>
  );
}
