#!/usr/bin/env node
// Generate Tinycast/Core/Calculator/CurrencyData.generated.swift.
//
// Usage: node Tools/gen-currencies.js [currencies.json cldr-currencies.json]
// Downloads the sources when paths aren't given. Run occasionally, commit the output.
//
// Two sources, joined on the ISO code:
//   - Frankfurter decides *which* currencies exist — it's the same feed CurrencyRateStore pulls
//     rates from, so the table can never list a currency the app can't price.
//   - CLDR decides what humans *call* them: display name, currency sign, and the singular/plural
//     noun. Read from the pinned cldr-json checkout rather than the host's `Intl`, whose output
//     shifts with the local ICU version and would make this file unreproducible.
//
// Only unambiguous data is emitted. A sign or noun claimed by more than one currency is left out
// and decided by hand in CalcCurrency.swift, because picking one is a product call, not a lookup.
"use strict";

const fs = require("fs");
const path = require("path");

const CURRENCIES = "https://api.frankfurter.dev/v2/currencies";
const CLDR =
  "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-numbers-full/main/en/currencies.json";

// The feed serves ~165 live currencies; a collapse well below that means a bad response, not a real change.
const MIN_EXPECTED = 120;
// `scope` defaults to live currencies, so retirement filtering is only a backstop. Thin markets and
// weekends leave a real currency a few days stale (4 is the observed worst case), so the cutoff has
// to be generous — a genuinely retired code trails by years (ATS ended 2002, BGN 2025).
const MAX_STALE_DAYS = 90;

async function load(url, argPath) {
  if (argPath) return JSON.parse(fs.readFileSync(argPath, "utf8"));
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} -> HTTP ${response.status}`);
  return response.json();
}

const fold = (s) => s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
// A sign has to be punctuation the tokenizer can recognise on sight. CLDR also lists bare Latin
// letters ("P" for BWP, "L" for HNL); those are indistinguishable from a word and must not appear.
const isSign = (s) => [...s].length === 1 && !/[\p{L}\p{N}]/u.test(s);

// Capitalise each word without touching the rest, so "UAE dirham" survives as "UAE Dirham".
const titleCase = (s) => s.replace(/(^|[\s(])(\p{Ll})/gu, (_, lead, c) => lead + c.toUpperCase());

/// The card's badge is a small pill, so prefer whichever CLDR form is shorter: `displayName` is the
/// title-cased label ("US Dollar"), but for a few currencies the singular is far tighter
/// ("United Arab Emirates Dirham" vs "UAE dirham").
function displayName(entry, fallback) {
  const long = entry?.displayName || fallback;
  const short = titleCase(entry?.["displayName-count-one"] || "");
  return short && short.length < long.length ? short : long;
}

/// Keep only the entries exactly one currency lays claim to.
function unambiguous(claims) {
  return new Map(
    [...claims].filter(([, owners]) => owners.size === 1).map(([key, owners]) => [key, [...owners][0]]),
  );
}

function claim(map, key, code) {
  if (!map.has(key)) map.set(key, new Set());
  map.get(key).add(code);
}

function swiftString(value) {
  if (value.includes('"') || value.includes("\\")) throw new Error(`unsafe literal ${JSON.stringify(value)}`);
  return `"${value}"`;
}

async function main() {
  const currencies = await load(CURRENCIES, process.argv[2]);
  const cldr = await load(CLDR, process.argv[3]);
  if (!Array.isArray(currencies) || currencies.length === 0)
    throw new Error("expected a non-empty array of currencies");
  const names = cldr?.main?.en?.numbers?.currencies;
  if (!names) throw new Error("unexpected CLDR shape: main.en.numbers.currencies missing");

  const latest = currencies.reduce((max, c) => (c.end_date > max ? c.end_date : max), "");
  const cutoff = new Date(Date.parse(latest) - MAX_STALE_DAYS * 86400_000).toISOString().slice(0, 10);
  const live = currencies
    .filter((c) => c.end_date >= cutoff)
    .sort((a, b) => a.iso_code.localeCompare(b.iso_code));
  if (live.length < MIN_EXPECTED) throw new Error(`suspiciously few currencies: ${live.length}`);

  const signClaims = new Map();
  const narrowClaims = new Map();
  const wordClaims = new Map();
  const rows = [];
  let uncovered = 0;

  for (const entry of live) {
    const code = entry.iso_code;
    if (!/^[A-Z]{3}$/.test(code)) throw new Error(`unexpected ISO code ${JSON.stringify(code)}`);
    const cldrEntry = names[code];
    if (!cldrEntry) uncovered += 1;

    // CLDR's label is the one people read ("US Dollar"); the feed's is the formal registry name
    // ("United States Dollar"). Fall back to the feed for codes CLDR doesn't carry (GGP/IMP/JEP).
    rows.push([code, displayName(cldrEntry, entry.name)]);
    if (!cldrEntry) continue;

    if (cldrEntry.symbol && isSign(cldrEntry.symbol)) claim(signClaims, cldrEntry.symbol, code);
    if (cldrEntry["symbol-alt-narrow"] && isSign(cldrEntry["symbol-alt-narrow"]))
      claim(narrowClaims, cldrEntry["symbol-alt-narrow"], code);

    // The noun is the last word of the name ("US dollars" -> "dollars"). Accented forms are claimed
    // both as written and folded, so "krónur" and "kronur" both resolve without a US keyboard.
    for (const field of ["displayName-count-one", "displayName-count-other"]) {
      const word = (cldrEntry[field] || "").toLowerCase().split(/\s+/).filter(Boolean).pop() || "";
      if (word.length < 3 || !/^\p{L}+$/u.test(word)) continue;
      for (const form of new Set([word, fold(word), fold(word).replace(/[^a-z]/g, "")]))
        if (form.length >= 3) claim(wordClaims, form, code);
    }
  }

  // The standard symbol wins: CLDR writes every dollar but USD as "CA$"/"A$"/"NT$", which is exactly
  // the tie-break. Narrow symbols only fill gaps, where they too are unique (₽ for RUB, ฿ for THB).
  const signs = unambiguous(signClaims);
  for (const [sign, code] of unambiguous(narrowClaims)) if (!signs.has(sign)) signs.set(sign, code);
  const aliases = unambiguous(wordClaims);

  const out = path.resolve(__dirname, "..", "Tinycast/Core/Calculator/CurrencyData.generated.swift");
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(
    out,
    "// Generated by Tools/gen-currencies.js — do not edit by hand.\n" +
      `// Codes from ${CURRENCIES} (live as of ${latest}); names, signs and nouns from Unicode CLDR (en).\n` +
      "// Ambiguous signs and nouns are deliberately absent — CalcCurrency.swift decides those.\n" +
      "enum CurrencyData {\n" +
      "    /// Every currency the rate feed still publishes, as (ISO 4217 code, display name).\n" +
      "    static let all: [(code: String, name: String)] = [\n" +
      rows.map(([c, n]) => `        (${swiftString(c)}, ${swiftString(n)}),`).join("\n") +
      "\n    ]\n\n" +
      "    /// Currency sign → ISO code, lowercased to match the tokenizer's ident form. Only signs CLDR\n" +
      "    /// assigns to exactly one currency, so `$` is USD and `¥` is JPY without any guessing here.\n" +
      "    static let signs: [Character: String] = [\n" +
      [...signs]
        .sort((a, b) => a[1].localeCompare(b[1]))
        .map(([s, c]) => `        ${swiftString(s)}: ${swiftString(c.toLowerCase())},`)
        .join("\n") +
      "\n    ]\n\n" +
      "    /// Currency noun → ISO code, for nouns exactly one currency uses. Contested ones\n" +
      "    /// (`dollars`, `pounds`, `francs`…) are absent by design; CalcCurrency assigns those.\n" +
      "    static let aliases: [String: String] = [\n" +
      [...aliases]
        .sort((a, b) => a[0].localeCompare(b[0]))
        .map(([w, c]) => `        ${swiftString(w)}: ${swiftString(c)},`)
        .join("\n") +
      "\n    ]\n" +
      "}\n",
  );
  console.log(
    `wrote ${out} — ${rows.length} currencies as of ${latest} ` +
      `(${currencies.length - live.length} retired, ${uncovered} without CLDR names), ` +
      `${signs.size} signs, ${aliases.size} aliases`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
