#!/usr/bin/env node
// Generate Tinycast/Features/Calculator/Model/CurrencyData.generated.swift.
//
// Usage: node Scripts/gen-currencies.js [rates.json cldr-currencies.json cldr-currency-data.json]
// Downloads the sources when paths aren't given. Run occasionally, commit the output.
//
// Three sources, joined on the ISO code:
//   - The fiat rate feed decides *which* currencies exist — the same feed CurrencyRateStore pulls
//     rates from, so the table can never list a currency the app can't price.
//   - CLDR's supplemental currency data decides which of those are still *in use*. The feed carries
//     no retirement dates and happily quotes codes their countries abandoned years ago.
//   - CLDR's `en` numbers data decides what humans *call* them: display name, currency sign, and the
//     singular/plural noun. Read from the pinned cldr-json checkout rather than the host's `Intl`,
//     whose output shifts with the local ICU version and would make this file unreproducible.
//
// Only unambiguous data is emitted. A sign or noun claimed by more than one currency is left out
// and decided by hand in CalcCurrency.swift, because picking one is a product call, not a lookup.
// Crypto is hand-written in CalcCurrency.swift too — no standards body names it.
"use strict";

const fs = require("fs");
const path = require("path");

const RATES = "https://backend.raycast.com/api/v1/currencies";
const CLDR = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json";
const CLDR_NAMES = `${CLDR}/cldr-numbers-full/main/en/currencies.json`;
const CLDR_CURRENCY_DATA = `${CLDR}/cldr-core/supplemental/currencyData.json`;

// The feed serves ~170 codes and ~159 survive the filter; well below that is a bad response.
const MIN_EXPECTED = 150;
// The crypto table in CalcCurrency.swift owns this one, and prices it from the dedicated feed.
const CRYPTO_OWNED = new Set(["BTC"]);
// CLDR carries no name for the Crown Dependencies' pounds, and the feed supplies no names at all.
const UNNAMED = { GGP: "Guernsey Pound", IMP: "Isle of Man Pound", JEP: "Jersey Pound" };

async function load(url, argPath) {
  if (argPath) return JSON.parse(fs.readFileSync(argPath, "utf8"));
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} -> HTTP ${response.status}`);
  return response.json();
}

const fold = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "");
// A sign has to be punctuation the tokenizer can recognise on sight. CLDR also lists bare Latin
// letters ("P" for BWP, "L" for HNL); those are indistinguishable from a word and must not appear.
const isSign = (s) => [...s].length === 1 && !/[\p{L}\p{N}]/u.test(s);

// Capitalise each word without touching the rest, so "UAE dirham" survives as "UAE Dirham".
const titleCase = (s) => s.replace(/(^|[\s(])(\p{Ll})/gu, (_, lead, c) => lead + c.toUpperCase());

// The noun is taken as the last word of the name, which only fails where that word isn't a noun for
// the money itself: nobody asks to convert "1 rights". Naming the exceptions beats parsing grammar.
const NOT_NOUNS = new Set(["rights"]);

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

/// Codes CLDR knows at all, and codes it still shows some region using. A code CLDR has never heard
/// of stays in: absence of evidence isn't retirement, and it is what keeps CNH, XAU, XDR and the
/// Crown Dependencies' pounds, none of which are any region's tender.
function inUse(currencyData) {
  const known = new Set();
  const live = new Set();
  for (const entries of Object.values(currencyData.region)) {
    for (const entry of entries) {
      for (const [code, meta] of Object.entries(entry)) {
        known.add(code);
        if (!("_to" in meta)) live.add(code);
      }
    }
  }
  return (code) => live.has(code) || !known.has(code);
}

async function main() {
  const feed = await load(RATES, process.argv[2]);
  const cldr = await load(CLDR_NAMES, process.argv[3]);
  const supplemental = await load(CLDR_CURRENCY_DATA, process.argv[4]);
  const base = feed?.source;
  const quotes = feed?.quotes;
  // An error body arrives with HTTP 200, so the flag is the only thing that says the table is real.
  if (feed?.success !== true) throw new Error("the rate feed reported failure");
  if (!base || !quotes || typeof quotes !== "object")
    throw new Error("unexpected feed shape: source/quotes missing");
  const names = cldr?.main?.en?.numbers?.currencies;
  if (!names) throw new Error("unexpected CLDR shape: main.en.numbers.currencies missing");
  if (!supplemental?.supplemental?.currencyData?.region)
    throw new Error("unexpected CLDR shape: supplemental.currencyData.region missing");

  // Quotes are keyed "<base><code>" and omit the base's own row, so it has to be added back.
  const quoted = new Set([base]);
  for (const pair of Object.keys(quotes)) {
    if (pair.length === 6 && pair.startsWith(base)) quoted.add(pair.slice(3));
  }

  const stillInUse = inUse(supplemental.supplemental.currencyData);
  const codes = [...quoted]
    .filter((code) => /^[A-Z]{3}$/.test(code) && !CRYPTO_OWNED.has(code) && stillInUse(code))
    .sort();
  const retired = quoted.size - CRYPTO_OWNED.size - codes.length;
  const asOf = new Date((feed.timestamp || Date.now() / 1000) * 1000).toISOString().slice(0, 10);
  if (codes.length < MIN_EXPECTED) throw new Error(`suspiciously few currencies: ${codes.length}`);

  const signClaims = new Map();
  const narrowClaims = new Map();
  const wordClaims = new Map();
  const rows = [];
  let uncovered = 0;

  for (const code of codes) {
    const cldrEntry = names[code];
    if (!cldrEntry) uncovered += 1;

    rows.push([code, displayName(cldrEntry, UNNAMED[code] || code)]);
    if (!cldrEntry) continue;

    if (cldrEntry.symbol && isSign(cldrEntry.symbol)) claim(signClaims, cldrEntry.symbol, code);
    if (cldrEntry["symbol-alt-narrow"] && isSign(cldrEntry["symbol-alt-narrow"]))
      claim(narrowClaims, cldrEntry["symbol-alt-narrow"], code);

    // The noun is the last word of the name ("US dollars" -> "dollars"). Accented forms are claimed
    // both as written and folded, so "krónur" and "kronur" both resolve without a US keyboard.
    for (const field of ["displayName-count-one", "displayName-count-other"]) {
      const word = (cldrEntry[field] || "").toLowerCase().split(/\s+/).filter(Boolean).pop() || "";
      if (word.length < 3 || !/^\p{L}+$/u.test(word) || NOT_NOUNS.has(word)) continue;
      for (const form of new Set([word, fold(word), fold(word).replace(/[^a-z]/g, "")]))
        if (form.length >= 3) claim(wordClaims, form, code);
    }
  }

  // The standard symbol wins: CLDR writes every dollar but USD as "CA$"/"A$"/"NT$", which is exactly
  // the tie-break. Narrow symbols only fill gaps, where they too are unique (₽ for RUB, ฿ for THB).
  const signs = unambiguous(signClaims);
  for (const [sign, code] of unambiguous(narrowClaims)) if (!signs.has(sign)) signs.set(sign, code);
  const aliases = unambiguous(wordClaims);

  const out = path.resolve(__dirname, "..", "Tinycast/Features/Calculator/Model/CurrencyData.generated.swift");
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(
    out,
    "// Generated by Scripts/gen-currencies.js — do not edit by hand.\n" +
      `// Codes from the fiat rate feed (as of ${asOf}), minus those Unicode CLDR records as retired;\n` +
      "// names, signs and nouns from CLDR (en). Ambiguous signs and nouns are deliberately absent,\n" +
      "// and so is crypto — CalcCurrency.swift decides both.\n" +
      "enum CurrencyData {\n" +
      "    /// Every fiat currency the rate feed prices, as (ISO 4217 code, display name).\n" +
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
    `wrote ${out} — ${rows.length} currencies ` +
      `(${retired} retired, ${uncovered} without CLDR names), ` +
      `${signs.size} signs, ${aliases.size} aliases`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
