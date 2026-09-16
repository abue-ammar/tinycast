import { ShieldCheck } from "lucide-react";
import {
  defaultSwitches,
  permissionNote,
  privacyStats,
  type DefaultSwitch,
} from "../data/privacy";
import { cn } from "../lib/cn";
import { featureIcons } from "./ui/feature-icons";
import { Section } from "./ui/section";

// A picture of a switch, not a control: the section shows defaults, it doesn't change them.
function SwitchGlyph({ isOn }: { isOn: boolean }) {
  return (
    <span
      aria-hidden="true"
      className={cn(
        "relative inline-flex h-5 w-9 shrink-0 rounded-full",
        isOn ? "bg-violet" : "bg-tint/15",
      )}
    >
      <span
        className={cn(
          "absolute top-0.5 size-4 rounded-full bg-white shadow-sm",
          isOn ? "left-4.5" : "left-0.5",
        )}
      />
    </span>
  );
}

function SwitchCard({ icon, name, note, isOn }: DefaultSwitch) {
  const Icon = featureIcons[icon];
  return (
    <li className="flex flex-col rounded-xl bg-canvas p-4">
      <span className="flex items-center justify-between">
        <span
          className={cn(
            "flex size-9 items-center justify-center rounded-lg",
            isOn
              ? "bg-violet/15 text-violet-bright"
              : "bg-tint/5 text-fg-muted",
          )}
        >
          <Icon size={17} strokeWidth={1.8} aria-hidden="true" />
        </span>
        <span className="sr-only">{isOn ? "On" : "Off"} by default</span>
        <SwitchGlyph isOn={isOn} />
      </span>
      <span className="mt-4 text-body font-medium text-fg">{name}</span>
      <span className="mt-1 text-small text-fg-muted">{note}</span>
    </li>
  );
}

export function Privacy() {
  const offCount = defaultSwitches.filter((item) => !item.isOn).length;

  return (
    <Section
      id="privacy"
      index={3}
      label="Privacy"
      title="Nothing turns on until you do."
      intro="A fresh install is a launcher, a calculator and your clipboard. Everything else waits for you to switch it on, and none of it needs an account."
    >
      <dl className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {privacyStats.map((stat) => (
          <div
            key={stat.label}
            className="flex flex-col-reverse rounded-xl bg-tint/4 px-5 py-4"
          >
            <dt className="text-small text-fg-muted">{stat.label}</dt>
            <dd className="text-heading text-fg">{stat.value}</dd>
          </div>
        ))}
      </dl>

      <figure className="mt-4 rounded-2xl bg-tint/4 p-2">
        <figcaption className="flex items-center justify-between gap-3 px-3 pb-3 pt-2.5">
          <span className="text-small font-medium text-fg">
            Settings, on a fresh install
          </span>
          <span className="rounded-full bg-kbd-bg px-2.5 py-0.5 text-caption font-medium text-kbd">
            {offCount} of {defaultSwitches.length} off
          </span>
        </figcaption>
        <ul className="grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
          {defaultSwitches.map((item) => (
            <SwitchCard key={item.name} {...item} />
          ))}
        </ul>
        <p className="flex gap-3 px-3 pb-2 pt-4 text-small text-fg-muted">
          <ShieldCheck
            size={16}
            className="mt-0.5 shrink-0 text-violet-bright"
            aria-hidden="true"
          />
          {permissionNote}
        </p>
      </figure>
    </Section>
  );
}
