---
title: Calculator
description: Math, units, live currency and crypto, and plain-English dates — inline as you type.
---

Type a calculation into the launcher and the answer is pinned above the results. There is no mode to
enter; it evaluates as you type.

<kbd>↵</kbd> copies the answer and records it to **Calculator History**.

## Arithmetic

`4(2+3)` is 20. `2pi`, `2sqrt(9)` and `(2+3)(2+3)` all work, and `6/2(1+2)` agrees with
`6/2*(1+2)`. Adjacent bare numbers never multiply, so `5 3` stays an app search.

`mod` is spelled out rather than `%`, sits at multiply/divide precedence, and takes the sign of the
dividend: `-10 mod 3` is `-1`.

`10k` is `10,000`. Scientific notation works — `1e5`, `5e-3km`, `3e+2` — while `2e` and `2 e` stay
2 × Euler's _e_.

**A trailing operator keeps the last complete result visible.** `10 +` shows `10`, and
`10kg + 500g +` shows `10,500 g`, so the card does not flicker while you type.

## Units

**The last unit you typed decides the answer's unit.**

| You type            | You get                                       |
| ------------------- | --------------------------------------------- |
| `5feet + 1m`        | `2.524 m`                                     |
| `10kg + 500g`       | `10,500 g`                                    |
| `1kg + 500g + 2lb`  | pounds                                        |
| `10kg + 500g to lb` | pounds — a trailing `to` overrides everything |

**Adjacency is composite notation, not addition.** `5 feet 3 inches` is `5.25 ft` and `1hr 30min` is
`1.5 hr`, answered in the _leading_ unit.

A bare number takes the unit written against it: `5kg+5` is `10 kg`, `$10 + 5` is `15.00 USD`.

Percentages are relative for `+` and `-` (`10kg + 20%` → `12 kg`) and a fractional scalar for `*` and
`/` (`10kg * 3%` → `0.3 kg`, `10kg / 25%` → `40 kg`).

A bare quantity auto-converts: `1m` gives feet and inches, `1hr` gives 60 min.

Multiplying two unit values is an error rather than a guess at a derived dimension. Affine
temperatures may only be added or subtracted within one scale.

## Currency and crypto

| You type                    | It means             |
| --------------------------- | -------------------- |
| `1 euro to dollars`         | Named currencies     |
| `€20 to GBP` / `20€ to GBP` | Symbols, either side |
| `eur to usd`                | Amount 1 implied     |
| `1 btc to eur`              | Crypto               |
| `$10 + €5`                  | Mixed arithmetic     |

159 fiat codes plus a hand-picked crypto list.

**A bare amount answers in your Mac's own currency.** On a machine set to Bangladesh, `1 usd` reads
`122.84 BDT`. That comes from your region preference — **nothing ever asks for your location**.

### Ambiguity

Shared nouns are assigned deliberately: `dollars` (22 currencies), `francs` (10), `pounds` (9),
`pesos` (8), `rupees` (6). A genuinely ambiguous word produces **no card at all** — `krona` is both
SEK and ISK, so Tinycast declines to guess.

Slang is deliberately unsupported: **`quid` and `bucks` do not work.** `rmb` and `renminbi` do —
ISO 4217 names CNY "Yuan Renminbi", so those are the standard's own words rather than slang.

Units run before currency, so `10 pounds to kg` is weight, `10 pounds to euros` is money, and
`1 cup to ml` stays volume even though `CUP` is the Cuban peso. Crypto tickers outrank generated
nouns: `1 sol` is Solana, while `soles` and `pen` reach the Peruvian sol.

### Rates

Cached locally and refreshed every 24 hours, measured from when the file was written — so relaunching
never re-fetches a fresh snapshot, and a cold start with a same-day cache makes **zero** network
requests.

Crypto is best-effort; a run that misses coins answers for the session and retries in 30 minutes.

Offline, the last snapshot keeps answering. With no snapshot at all, the card says so rather than
guessing. An unquoted code reports `No exchange rate for <CODE>.`

Money rounds to two decimals, widening to four significant digits below a cent, always in plain
notation: `1 IDR to USD` is `0.00005539 USD`, never `5.539e-05`.

## Dates and times

Four grammars:

| Grammar                | Example                             |
| ---------------------- | ----------------------------------- |
| Time until a moment    | `hrs till 9am`, `days till 9april`  |
| Time since a moment    | `days since 9jul`, `hrs since noon` |
| A moment ± a duration  | `today + 3 weeks`, `now + 90 min`   |
| Difference between two | `jul 4 - today`                     |

`till` takes the next occurrence, `since` the most recent past one; an absolute date ignores the
bias. The difference grammar needs at least one operand containing a letter, so `5/2 - 1/2` stays
arithmetic.

Two-digit years: 00–68 are 2000s, 69–99 are 1900s.

## Other conversions

Base conversion works both ways — `0xff` reads Hexadecimal → Decimal.

## Errors

Errors are reserved for real mistakes: two incompatible units (`1kg + 1m`), or a unit against a
currency (`Cannot convert Currency to Weight.`).

Everything else stays silent rather than flashing an error mid-keystroke. A half-typed expression is
not a mistake, it is a half-typed expression.

## History

**Calculator History** is its own screen, reached by the command of that name. It is deliberately
outside the <kbd>⇥</kbd> cycle; leave with <kbd>⎋</kbd> or a bare <kbd>⌫</kbd>.

| Action             | Shortcut                             |
| ------------------ | ------------------------------------ |
| Copy Answer        | <kbd>↵</kbd>                         |
| Copy Expression    | <kbd>⌘</kbd><kbd>↵</kbd>             |
| Delete Entry       | <kbd>⌃</kbd><kbd>X</kbd>             |
| Delete All Entries | <kbd>⌃</kbd><kbd>⇧</kbd><kbd>X</kbd> |
