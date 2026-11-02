"use client";

import { Info, LoaderCircle, Lock } from "lucide-react";
import { useEffect, useState } from "react";
import {
  cardSupport,
  maxAmount,
  plans,
  presetAmounts,
  type Plan,
} from "../../data/support";
import { cn } from "../../lib/cn";
import { PolarLogo, SupportIcon } from "../ui/icon";
import { ChoiceChip } from "./choice-chip";

async function createCheckout(plan: Plan, amount: number): Promise<string> {
  const res = await fetch("/api/checkout", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ plan, amount }),
  });
  const body = (await res.json().catch(() => null)) as {
    url?: string;
    error?: string;
  } | null;
  if (!res.ok || !body?.url) {
    throw new Error(body?.error ?? "The checkout could not be opened.");
  }
  return body.url;
}

export function CheckoutPanel() {
  const [plan, setPlan] = useState<Plan>("one-time");
  const [preset, setPreset] = useState<number | null>(null);
  const [custom, setCustom] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const amount = preset ?? Number(custom);
  const valid = Number.isInteger(amount) && amount >= 1 && amount <= maxAmount;
  const cadence = plan === "monthly" ? " / month" : "";
  const action = plan === "monthly" ? "Subscribe for" : "Buy for";

  // Back from Polar restores this page from the back-forward cache, spinner and all.
  useEffect(() => {
    const reset = (event: PageTransitionEvent) => {
      if (event.persisted) setPending(false);
    };
    window.addEventListener("pageshow", reset);
    return () => window.removeEventListener("pageshow", reset);
  }, []);

  async function open() {
    if (!valid || pending) return;
    setPending(true);
    setError(null);
    try {
      // Polar's own page, so the address bar shows who takes the payment.
      window.location.assign(await createCheckout(plan, amount));
    } catch (cause) {
      setPending(false);
      setError(
        cause instanceof Error
          ? cause.message
          : "The checkout could not be opened.",
      );
    }
  }

  return (
    <>
      <p className="text-small text-fg-muted">{cardSupport.intro}</p>
      <fieldset className="mt-4">
        <legend className="sr-only">Frequency</legend>
        <div className="flex flex-wrap gap-2">
          {plans.map((option) => (
            <ChoiceChip
              key={option.id}
              name="plan"
              value={option.id}
              checked={plan === option.id}
              onChange={() => setPlan(option.id)}
            >
              {option.label}
            </ChoiceChip>
          ))}
        </div>
      </fieldset>

      <fieldset className="mt-5">
        <legend className="font-mono text-eyebrow uppercase text-fg-muted">
          Price (USD{cadence})
        </legend>
        <div className="mt-2 grid grid-cols-4 gap-2">
          {presetAmounts.map((value) => (
            <button
              key={value}
              type="button"
              aria-pressed={preset === value}
              onClick={() => {
                setPreset(value);
                setCustom("");
              }}
              className={cn(
                "h-11 rounded-lg font-mono text-body transition-[box-shadow,color,background-color]",
                preset === value
                  ? "bg-violet/12 text-fg shadow-[inset_0_0_0_1.5px_var(--color-violet)]"
                  : "text-fg-muted shadow-key hover:text-fg hover:shadow-key-hover",
              )}
            >
              ${value}
            </button>
          ))}
        </div>
        <label
          className={cn(
            "mt-2 flex h-11 cursor-text items-center gap-1 rounded-lg bg-well px-4 transition-shadow",
            "focus-within:shadow-[inset_0_0_0_1.5px_var(--color-violet)]",
            custom !== "" && "shadow-[inset_0_0_0_1.5px_var(--color-violet)]",
          )}
        >
          <span className="font-mono text-body text-fg-subtle">$</span>
          <input
            inputMode="numeric"
            placeholder="Other price"
            aria-label={`Other price in US dollars${cadence}`}
            value={custom}
            onFocus={() => setPreset(null)}
            onChange={(event) => {
              setPreset(null);
              setCustom(event.target.value.replace(/\D/g, "").slice(0, 5));
            }}
            className="w-full bg-transparent font-mono text-body text-fg outline-none placeholder:font-sans placeholder:text-fg-subtle"
          />
        </label>
        <button
          type="button"
          onClick={open}
          disabled={!valid || pending}
          className="mt-2 inline-flex h-11 w-full items-center justify-center gap-2 rounded-lg bg-violet text-small font-medium text-white transition-colors hover:bg-violet-deep active:translate-y-px disabled:cursor-not-allowed disabled:opacity-50"
        >
          {pending ? (
            <LoaderCircle size={16} className="animate-spin" />
          ) : (
            <SupportIcon size={16} />
          )}
          {valid ? `${action} $${amount}${cadence}` : "Choose a price"}
        </button>
        <p className="mt-3 flex gap-2 text-caption text-fg-muted">
          <Info
            size={14}
            className="mt-0.5 shrink-0 text-fg-subtle"
            aria-hidden="true"
          />
          {plan === "monthly"
            ? "Renews monthly until you cancel."
            : "A one-time purchase that doesn't renew."}
        </p>
        <p
          role="status"
          className={cn("text-small text-fg", error ? "mt-3" : "sr-only")}
        >
          {error}
        </p>
      </fieldset>

      <div className="mt-auto pt-5">
        <p className="flex gap-2.5 border-t border-border pt-4 text-small text-fg-muted">
          <Lock size={16} className="mt-1 shrink-0" aria-hidden="true" />
          <span>
            Payments secured by{" "}
            <a
              href="https://polar.sh"
              target="_blank"
              rel="noreferrer"
              className="text-fg transition-opacity hover:opacity-80"
            >
              <PolarLogo height={14} className="inline-block align-[-2px]" />
            </a>
            .
          </span>
        </p>
      </div>
    </>
  );
}
