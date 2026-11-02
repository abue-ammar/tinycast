"use client";

import { Bitcoin, CreditCard, type LucideIcon } from "lucide-react";
import { useEffect, useState, type ReactNode } from "react";
import { methods, type Method, type Plan } from "../../data/support";
import { cn } from "../../lib/cn";
import { CheckoutPanel } from "./checkout-panel";
import { CryptoPanel } from "./crypto-panel";
import { ThankYou } from "./thank-you";

const THANKS_PARAM = "thanks";

const methodIcons: Record<Method, LucideIcon> = {
  crypto: Bitcoin,
  card: CreditCard,
};

function parsePlan(value: string | null): Plan | null {
  return value === "monthly" || value === "one-time" ? value : null;
}

function MethodTabs({
  value,
  onChange,
}: {
  value: Method;
  onChange: (method: Method) => void;
}) {
  return (
    <fieldset className="flex gap-6 border-b border-border px-5 sm:px-6">
      <legend className="sr-only">Payment method</legend>
      {methods.map((method) => {
        const Icon = methodIcons[method.id];
        const isSelected = method.id === value;
        return (
          <label
            key={method.id}
            className={cn(
              "relative flex h-12 cursor-pointer items-center gap-2 text-small font-medium transition-colors",
              "has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-violet-bright",
              isSelected
                ? "text-fg after:absolute after:inset-x-0 after:-bottom-px after:h-0.5 after:bg-violet"
                : "text-fg-muted hover:text-fg",
            )}
          >
            <input
              type="radio"
              name="method"
              value={method.id}
              checked={isSelected}
              onChange={() => onChange(method.id)}
              className="sr-only"
            />
            <Icon size={16} aria-hidden="true" />
            {method.label}
          </label>
        );
      })}
    </fieldset>
  );
}

// Both panels share one grid cell, so on wider screens the card keeps the taller one's height.
function MethodPanel({
  isActive,
  children,
}: {
  isActive: boolean;
  children: ReactNode;
}) {
  return (
    <div
      inert={!isActive}
      className={cn(
        "flex flex-col [grid-area:1/1]",
        !isActive && "invisible max-sm:hidden",
      )}
    >
      {children}
    </div>
  );
}

type Props = {
  intro: ReactNode;
};

export function SupportFlow({ intro }: Props) {
  const [returned, setReturned] = useState<Plan | null>(null);
  const [method, setMethod] = useState<Method>("card");

  // Polar's return adds ?thanks=<plan>; drop it so a reload shows the card again.
  useEffect(() => {
    const url = new URL(window.location.href);
    const plan = parsePlan(url.searchParams.get(THANKS_PARAM));
    if (!plan) return;
    url.searchParams.delete(THANKS_PARAM);
    window.history.replaceState(window.history.state, "", url);
    // oxlint-disable-next-line react/set-state-in-effect -- URL is only readable after hydration
    setReturned(plan);
  }, []);

  return (
    <div className="grid items-start gap-10 lg:grid-cols-[minmax(0,1fr)_580px] lg:gap-20">
      {intro}
      <div className="rise relative" style={{ animationDelay: "120ms" }}>
        <span
          aria-hidden="true"
          className="mark-bloom pointer-events-none absolute inset-x-0 -top-16 h-72 opacity-60"
        />
        <div className="relative lg:sticky lg:top-20">
          {returned ? (
            <ThankYou plan={returned} />
          ) : (
            <div className="rounded-2xl bg-surface shadow-key">
              <MethodTabs value={method} onChange={setMethod} />
              <div className="grid p-5 sm:p-6">
                <MethodPanel isActive={method === "card"}>
                  <CheckoutPanel />
                </MethodPanel>
                <MethodPanel isActive={method === "crypto"}>
                  <CryptoPanel />
                </MethodPanel>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
