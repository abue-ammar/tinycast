"use client";

import { Mail, TriangleAlert } from "lucide-react";
import { useState } from "react";
import { cryptoSupport, wallets } from "../../data/support";
import { CopyButton } from "../ui/copy-button";
import { ChoiceChip } from "./choice-chip";

const { unlisted } = cryptoSupport;
const mailto = `mailto:${unlisted.email}?subject=${encodeURIComponent(unlisted.subject)}`;

// Inline-blocks wrap between groups yet copy as one unbroken string.
function groupsOfFour(address: string): string[] {
  return address.match(/.{1,4}/g) ?? [];
}

export function CryptoPanel() {
  const [wallet, setWallet] = useState(wallets[0]);

  return (
    <>
      <p className="text-small text-fg-muted">{cryptoSupport.intro}</p>
      <fieldset className="mt-4">
        <legend className="sr-only">Network</legend>
        <div className="flex flex-wrap gap-2">
          {wallets.map((option) => (
            <ChoiceChip
              key={option.id}
              name="network"
              value={option.id}
              checked={option === wallet}
              onChange={() => setWallet(option)}
            >
              <img
                src={`/wallets/${option.id}.svg`}
                alt=""
                width={22}
                height={22}
                className="size-5.5"
              />
              {option.label}
            </ChoiceChip>
          ))}
        </div>
      </fieldset>

      <div className="mt-5 grid items-center gap-5 sm:grid-cols-[164px_minmax(0,1fr)]">
        {/* Every code is in the page from the start, so switching networks never waits on one. */}
        <div className="mx-auto w-full max-w-56 sm:max-w-none">
          {wallets.map((option) => (
            <img
              key={option.id}
              src={`/wallets/${option.id}-qr.svg`}
              alt={`QR code for the ${option.network} address`}
              width={164}
              height={164}
              hidden={option !== wallet}
              className="aspect-square w-full rounded-lg shadow-line"
            />
          ))}
        </div>

        <div className="min-w-0">
          <p className="font-mono text-eyebrow uppercase text-fg-muted">
            {wallet.network} address
          </p>
          <p className="mt-2 select-all rounded-lg bg-well px-4 py-3 font-mono text-small text-fg">
            {groupsOfFour(wallet.address).map((group, index) => (
              <span key={index} className="mr-[0.6ch] inline-block last:mr-0">
                {group}
              </span>
            ))}
          </p>
          <CopyButton
            key={wallet.id}
            text={wallet.address}
            subject={`${wallet.network} address`}
            className="mt-2 h-11 w-full justify-center gap-2 rounded-lg bg-action text-small text-action-fg hover:opacity-90 active:translate-y-px"
          />
          <p className="mt-3 flex gap-2 text-caption text-fg-muted">
            <TriangleAlert
              size={14}
              className="mt-0.5 shrink-0 text-fg-subtle"
              aria-hidden="true"
            />
            {cryptoSupport.warning(wallet.network)}
          </p>
        </div>
      </div>

      <div className="mt-auto pt-5">
        <p className="flex gap-2.5 border-t border-border pt-4 text-small text-fg-muted">
          <Mail size={16} className="mt-1 shrink-0" aria-hidden="true" />
          <span>
            {unlisted.lead}{" "}
            <a
              href={mailto}
              className="font-medium text-fg underline decoration-border-strong underline-offset-4 transition-colors hover:decoration-fg"
            >
              {unlisted.email}
            </a>
            .
          </span>
        </p>
      </div>
    </>
  );
}
