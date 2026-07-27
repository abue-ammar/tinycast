# Inline calculator

`Core/Calculator/` is a **Foundation-only** engine (no AppKit / SwiftUI imports) fronted by
`CalcMemo`, a one-deep memo mirroring `AppIndex`'s. It must stay Foundation-only because the
`Tools/calc-test.swift` harness compiles the real engine sources — including `CalcDateTime`. It is
also **pure**: the one input it can't compute, the FX rate table, is passed in (see Currency below).

## Evaluation pipeline

`CalcEngine.evaluate` runs:

1. Natural-language date/time (`CalcDateTime`, e.g. `hrs till 9am`, `days till 9april`,
   `today + 3 weeks`)
2. Numeric reject
3. Tokenize
4. Base conversion
5. Explicit unit conversion (`10km to mi`)
6. **Currency conversion** (`1 euro to dollars`, `€20 to GBP`)
7. **Bare-unit auto-conversion** (`1m` → feet + inches, `1hr` → 60 min, via
   `CalcUnits.parseBareConversion` + the `autoTargets` map)
8. Plain arithmetic

Date/time depends on the clock, so it takes an injected `now` / `calendar` — the public `evaluate(_:)`
uses the live clock, and `evaluate(_:now:calendar:)` lets `calc-test.swift` assert exact strings
against a fixed clock.

## Currency

`CalcCurrency` mirrors `CalcUnits`' shape: an alias table (ISO code, singular/plural name, nicknames,
and the `€ £ $ ¥ ₹ …` signs the tokenizer folds to codes) plus a `parseConversion` over the same
`expr from (to|in|->) to` token shape, so `eur to usd` implies an amount of 1 exactly like `m to ft`.
A leading sign is swapped back into amount-first order, so `€20 to GBP` and `20€ to GBP` parse alike.

Order is the whole disambiguation story. Currency runs **after** the unit path, so a query both sides
of which are compatible units stays a measurement: `10 pounds to kg` is weight, `10 pounds to euros`
is money. A currency on one side and a unit on the other produces the same friendly category error as
any other mismatch (`Cannot convert Currency to Weight.`).

Rates come from `CurrencyRateStore` (`Core/`, owned by `AppCore`): one key-less USD-based table from
exchangerate-api, cached at `~/Library/Caches/<bundle-id>/currency-rates.json`, refreshed every 6h
with a 15-minute retry after a failure. Offline, the last snapshot keeps answering; with no snapshot
at all the card says so rather than guessing, and a currency the table doesn't quote reports
`No exchange rate for <CODE>.` The store hands `CalcEngine.evaluate` a finished `CurrencyRates`
value — the engine never fetches, which is what keeps it Foundation-only and testable. `CalcMemo`
keys its memo on the snapshot's `fetchedAt`, so a fresh table re-evaluates without diffing 160 rates.

Money rounds to two decimals (`CalcFormatter.currency`), widening to four significant digits below a
cent so `1 JPY to USD` reads `0.00611 USD` instead of `0.00`.

## Result and rendering

`CalcResult` carries an `expression` (left), a `display` / `copyText` payload (right), and optional
`sourceBadge` / `targetBadge` word-name pills. `CalculatorCard` renders it as a two-column card.

When the launcher or Calculator History query evaluates to a result the card is pinned at the top of
the list (flat selection index 0, shifting rows by one) and Enter copies the answer + records it to
`CalculatorHistoryStore`.
