import { ArrowRight, Info } from "lucide-react";
import Image from "next/image";
import { migration } from "../data/migration";
import { asset } from "../lib/asset";
import { Link } from "./ui/link";
import { Section } from "./ui/section";

export function Switch() {
  return (
    <Section
      id="switch"
      index={5}
      label="Moving over"
      title={migration.title}
      intro={migration.intro}
    >
      <div className="grid items-start gap-10 lg:grid-cols-[minmax(0,0.85fr)_minmax(0,1fr)]">
        {/* A real sequence, so these carry numbers. */}
        <ol className="flex flex-col gap-6">
          {migration.steps.map((step, i) => (
            <li key={step.title} className="flex gap-4">
              <span
                aria-hidden="true"
                className="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-full bg-violet/15 text-caption font-semibold text-violet-bright"
              >
                {i + 1}
              </span>
              <span className="min-w-0">
                <h3 className="text-body font-medium text-fg">{step.title}</h3>
                <p className="mt-1 text-small text-fg-muted">{step.body}</p>
              </span>
            </li>
          ))}
        </ol>

        <div className="overflow-hidden rounded-2xl ring-1 ring-border">
          <Image
            src={asset("import.png")}
            width={1800}
            height={1192}
            alt="Tinycast's Backup settings pane with a Raycast export selected and a list of categories to import."
            className="block h-auto w-full"
          />
        </div>
      </div>

      <p className="mt-10 flex gap-3 text-small text-fg-muted">
        <Info
          size={16}
          aria-hidden="true"
          className="mt-0.5 shrink-0 text-violet-bright"
        />
        <span>
          <strong className="font-medium text-fg">
            {migration.requirement.title}.
          </strong>{" "}
          {migration.requirement.body}
        </span>
      </p>

      <p className="mt-6 text-small text-fg-muted">
        <span className="text-fg">Comes across: </span>
        {migration.transfers.join(" · ")}.{" "}
        <Link
          href="/docs/reference/import-from-raycast"
          className="inline-flex items-center gap-1 text-fg underline decoration-border-strong underline-offset-4 transition-colors hover:decoration-violet-bright"
        >
          Read the import guide
          <ArrowRight size={13} aria-hidden="true" />
        </Link>
      </p>
    </Section>
  );
}
