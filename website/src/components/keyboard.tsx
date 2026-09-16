import { shortcutRows } from "../data/shortcuts";
import { Link } from "./ui/link";
import { Section } from "./ui/section";

export function Keyboard() {
  return (
    <Section
      id="keyboard"
      index={4}
      label="Keyboard"
      title="Built for the keyboard."
      intro="Pick one shortcut to summon the palette. Everything after that is a key away, and keys follow their position, so any layout works."
    >
      <dl className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {shortcutRows.map((row) => (
          <div
            key={row.does}
            className="flex flex-col gap-3 rounded-xl bg-tint/4 p-4"
          >
            <dt>
              {/* The sans stack, not mono: no monospace face draws ⌘ ⌥ ⇧. */}
              <kbd className="inline-flex h-7 min-w-9 items-center justify-center gap-1 whitespace-nowrap rounded-md border border-border bg-surface px-2 font-sans text-small font-medium text-fg shadow-cap">
                {row.keys.join(" ")}
              </kbd>
            </dt>
            <dd className="text-small text-fg-muted">{row.does}</dd>
          </div>
        ))}
      </dl>
      <p className="mt-4 text-small text-fg-muted">
        Every other key, one table per screen, is in{" "}
        <Link
          href="/docs/reference/shortcuts"
          className="text-fg underline decoration-border-strong underline-offset-4 transition-colors hover:decoration-violet-bright"
        >
          Keyboard shortcuts
        </Link>
        .
      </p>
    </Section>
  );
}
