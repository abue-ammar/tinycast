import { Check, Gift, Star } from "lucide-react";
import { useEffect, useRef } from "react";
import { site } from "../../data/site";
import { thanks, type Plan } from "../../data/support";
import { Button } from "../ui/button";
import { DiscordLogo, SupportIcon } from "../ui/icon";

export function ThankYou({ plan }: { plan: Plan }) {
  const ref = useRef<HTMLDivElement>(null);

  // On a phone the card sits below the intro, so returning from Polar would hide the thanks.
  useEffect(() => {
    ref.current?.scrollIntoView({ behavior: "smooth", block: "center" });
  }, []);

  return (
    <div
      ref={ref}
      role="status"
      className="rise relative overflow-hidden rounded-2xl bg-surface px-6 pb-8 pt-10 text-center shadow-line sm:px-8"
    >
      <span
        aria-hidden="true"
        className="mark-bloom pointer-events-none absolute -top-24 left-1/2 size-56 -translate-x-1/2"
      />
      <span className="relative mx-auto flex size-14 items-center justify-center rounded-full bg-gradient-to-br from-violet-bright to-violet-deep text-white shadow-highlight">
        <SupportIcon size={28} />
      </span>
      <h2 className="relative mt-6 text-heading text-fg">{thanks.title}</h2>
      <p className="relative mx-auto mt-3 max-w-sm text-pretty text-body text-fg-muted">
        {thanks.body}
      </p>

      <ul className="mt-7 space-y-2.5 border-t border-border pt-6 text-left">
        {thanks.next[plan].map((line) => (
          <li key={line} className="flex gap-2.5 text-small text-fg-muted">
            <Check
              size={16}
              className="mt-0.5 shrink-0 text-violet-bright"
              aria-hidden="true"
            />
            {line}
          </li>
        ))}
      </ul>

      <div className="mt-7 rounded-xl bg-well p-5 text-left">
        <p className="flex items-center gap-2 text-small font-medium text-fg">
          <Gift size={16} className="text-violet-bright" aria-hidden="true" />
          {thanks.perks.title}
        </p>
        <p className="mt-1.5 text-pretty text-small text-fg-muted">
          {thanks.perks.body}
        </p>
        <Button href={thanks.perks.href} size="md" className="mt-4 w-full">
          {thanks.perks.action}
        </Button>
      </div>

      <p className="mt-7 text-small text-fg-subtle">{thanks.share}</p>
      <div className="mt-3 flex flex-wrap justify-center gap-2">
        <Button href={site.repo} variant="outline" size="md">
          <Star size={14} />
          Star on GitHub
        </Button>
        <Button href={site.community.discord} variant="outline" size="md">
          <DiscordLogo size={14} />
          Join the Discord
        </Button>
      </div>
    </div>
  );
}
