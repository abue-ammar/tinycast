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
4. Complete-prefix evaluation for a trailing binary operator (`10kg +` → `10 kg`)
5. Base conversion
6. Explicit unit conversion (`10km to mi`)
7. **Typed quantity arithmetic** (`10kg + 500g`, `$10 + €5`, `(1hr + 30min) to s`)
8. **Currency conversion** (`1 euro to dollars`, `€20 to GBP`)
9. **Bare-unit auto-conversion** (`1m` → feet + inches, `1hr` → 60 min, via
   `CalcUnits.parseBareConversion` + the `autoTargets` map)
10. Plain arithmetic

Date/time depends on the clock, so it takes an injected `now` / `calendar` — the public `evaluate(_:)`
uses the live clock, and `evaluate(_:now:calendar:)` lets `calc-test.swift` assert exact strings
against a fixed clock.

`CalcQuantity` is a separate typed precedence parser rather than a mode added to the scalar
`CalcParser`. Scalar `*` / `/` preserve the unit, compatible quantity division returns a scalar, and a
trailing `to` / `in` converts the complete expression. Percentages keep relative semantics for addition
(`10kg + 20%` → `12 kg`) and act as fractional scalars for multiplication and division
(`10kg * 3%` → `0.3 kg`, `10kg / 25%` → `40 kg`).

**The last unit typed decides the answer's unit.** `+` / `-` convert the *left* side into the right
operand's unit, so `5feet + 1m` is `2.524 m` and `10kg + 500g` is `10,500 g` — the unit you finished
writing is the one you were thinking in. Chains are left-associative, so `1kg + 500g + 2lb` ends in
pounds. A conversion suffix overrides it entirely (`10kg + 500g to lb`).

Adjacency is the exception. `5 feet 3 inches` and `1hr 30min` are one quantity in composite notation,
not a sum, so they answer in the *leading* unit (`5.25 ft`, `1.5 hr`). `QuantityParser.peekBinary`
already distinguishes the two — it reports `consumesToken: false` for the invisible `+` between
adjacent quantities — and `addOrSubtract` keys the unit choice off exactly that flag.

A bare number takes the unit it is written against: `5kg+5` is `10 kg`, `$10 + 5` is `15.00 USD`. Under
adjacency the same input stays silent, because there a bare trailing number is a unit still being
typed — `1hr 30` is one keystroke short of `1hr 30min`, and answering `31 hr` would be worse than
answering nothing.

Once an operator is involved the answer stays in the units written, so `2 * 5kg` is `10 kg`. Only a
bare quantity (`50cm`, `1m`) falls through to the keyword-less auto-conversion below.

Derived dimensions are deliberately not guessed: multiplying two unit values returns a clear error.
Affine temperatures may only be added or subtracted when both operands use the same scale; treating
an absolute Celsius/Fahrenheit value as a delta would silently produce physically incorrect answers.

Errors are reserved for input that can only be a mistake — two incompatible units (`1kg + 1m`), or a
unit against a currency. Everything else that cannot be evaluated stays silent rather than flashing a
card mid-keystroke.

An attached `k` is a thousands suffix (`10k` → `10,000`), while whitespace keeps Kelvin explicit
(`10 k to c`); the established attached Kelvin conversion form remains valid when the temperature
target makes the intent unambiguous (`273.15K to C`).

Scientific notation (`1e5` → `100,000`, `5e-3km`, `3e+2`) is read only while the exponent hugs the
mantissa, which is what keeps `2 e` and `2e` reading as 2 × Euler's *e* — an exponent needs digits
after the `e`. Like `10k`, it tokenizes as a shorthand rather than a plain literal, so a lone `1e5`
still earns a card where a lone `100000` deliberately doesn't. A literal that overflows to infinity
(`1e400`) is treated as non-calculator input, not as a card.

## Implicit multiplication

Juxtaposition means `*` at the same binding power as an explicit one (`4(2+3)` → 20, `2pi`,
`2sqrt(9)`, `(2+3)(2+3)`), so it binds tighter than `+` and looser than `^`, and `6/2(1+2)` agrees
with `6/2*(1+2)`. `CalcParser.parseExpression` checks it after `peekBinary()` fails and, unlike a real
operator, consumes no token before parsing the right operand.

The scalar side is deliberately narrow: only `(` or a name in `CalcParser.constants` / `functions`
starts an implicit product. Adjacent *numbers* never do — `5 3` stays an app search — and no unit or
currency name is a constant or function, so `10km` keeps its own path. `QuantityParser.peekBinary`
carries the same `(` rule so the typed side agrees (`$5(2)` → `10.00 USD`, `2(3)kg` → `6 kg`, matching
`2*(3)kg`); adjacency there still means the composite-quantity `+` described above, never a product.

## Modulo

`mod` is a binary operator at `*` / `/` precedence, computed with `truncatingRemainder` so the sign
follows the dividend (`-10 mod 3` → -1). It is spelled out on purpose: `%` already means percent, and
`20% - 5` offers no local signal to tell a percent from a remainder, so overloading the symbol would
silently rewrite expressions like `450 + 20% - 5`.

A query ending in a binary operator keeps the last complete prefix visible while the next operand is
being typed: `10 +` shows `10`, `10kg + 500g +` shows `10,500 g`, and `$10 +` shows `10.00 USD`
when currency is enabled. The prefix must itself be valid, so malformed input and incomplete
parentheses remain silent. The partial result preserves the complete prefix's target badge, making
the result's unit or currency explicit beneath the value. Only operators qualify — a trailing English
word such as `of` does not, so `10 of` stays a search. When the prefix was a conversion the card
echoes the typed text (`10km to mi ×`) rather than the conversion's own shortened echo, and
`tokenQuery` keeps radix prefixes so `0xff -` still reads Hexadecimal → Decimal.

## Currency

`CalcCurrency` mirrors `CalcUnits`' shape: a lookup table plus a `parseConversion` over the same
`expr from (to|in|->) to` token shape, so `eur to usd` implies an amount of 1 exactly like `m to ft`.
A leading sign is swapped back into amount-first order, so `€20 to GBP` and `20€ to GBP` parse alike.

The table is **generated except for the judgement calls**. `node Tools/gen-currencies.js` joins two
sources on the ISO code and emits `CurrencyData.generated.swift`:

- **Frankfurter** decides which currencies exist — the same feed the rates come from, so the table
  can never list something the app can't price. 165 codes.
- **CLDR** (`en`) decides what humans call them: display name, currency sign, singular/plural noun.
  Read from the pinned `cldr-json` checkout, not the host's `Intl`, whose output shifts with the
  local ICU version.

Only *unambiguous* CLDR data is emitted — 26 signs and 128 nouns. CLDR itself supplies the sign
tie-break: it writes every dollar but USD as `CA$`/`A$`/`NT$`, so plain `$` is claimed by exactly one
currency. Bare Latin letters CLDR lists as symbols (`P` for BWP, `L` for HNL) are dropped, since a
letter is indistinguishable from a word to the tokenizer. Accented nouns are emitted both as written
and folded, so `krónur` and `kronur` both resolve. The noun itself is the name's last word, which is
only wrong where that word isn't one — `NOT_NOUNS` in the generator drops those ("Special Drawing
Rights" is not a "rights").

What's left hand-written in `CalcCurrency.swift` is one table, `contested`: the nouns several
currencies share, where CLDR correctly refuses to choose and the calculator must. `dollars` is
claimed by 22 currencies, `francs` 10, `pounds` 9, `pesos` 8, `rupees` 6. CLDR says "US dollars" and
"Canadian dollars"; nothing in it says a bare "dollars" is USD. Words that stay genuinely ambiguous
are assigned to nobody — `krona` is both SEK and ISK, so it produces no card. Slang and synonyms
(`quid`, `bucks`, `rmb`) are deliberately *not* carried: they'd be hand-maintained data with no
source of truth.

Order is the whole disambiguation story. Currency runs **after** the unit path, so a query both sides
of which are compatible units stays a measurement: `10 pounds to kg` is weight, `10 pounds to euros`
is money, and `1 cup to ml` stays volume even though `CUP` is the Cuban peso. A currency on one side
and a unit on the other produces the same friendly category error as any other mismatch
(`Cannot convert Currency to Weight.`).

The typed quantity path uses the same ordering and injected rate snapshot. Currency arithmetic is
therefore deterministic and consent-gated: `$10 + €5` converts the left operand into euros when rates
are available — the same last-unit-typed rule the measurements follow — while the entire path is
absent when consent is off. Bare prefix and suffix signs (`$10`, `10$`) are accepted, and a conversion
suffix applies to the whole expression.

### Consent

Currency conversion reaches the network, so it ships **off** and stays off until the user turns it on
in Settings → Miscellaneous and accepts a sheet naming the provider, the request cadence and what
leaves the machine. Declining leaves it off; there is no "remind me later" state. Any future feature
that needs the network should follow the same shape rather than inventing a second one.

The gate is a type, not a boolean sprinkled around: `CalcEngine.evaluate` takes a `CurrencySource`
that is either `.off` or `.on(CurrencyRates?)`, and it **defaults to `.off`**, so a caller that
forgets to pass one gets the feature disabled rather than silently enabled. `.off` makes
`CalcCurrency.parseConversion` return nil before it parses anything, so a currency query produces no
card at all — not even the category-mismatch error, which would leak that the feature exists.
`.on(nil)` is the consented-but-not-yet-downloaded state, and that is what earns the "rates
unavailable" message.

`CurrencyRateStore` re-checks consent at every entry point rather than trusting a caller: reading the
cache at init, the `source` the engine is handed, `start()`, each turn of the refresh loop, and twice
around the network call itself — once before the request and once after the `await`, since consent
can be withdrawn while a response is in flight. Revoking cancels the loop, drops the snapshot and
deletes the cached file. The flag lives on the store, deliberately *not* in `AppSettings`:
`SettingsBackup` mirrors that type field-for-field, and importing a config must never be able to
grant network access.

For "revoking deletes the rates" to be true there has to be exactly one copy, so the fetch runs on a
private **cacheless** `URLSession` (`.ephemeral`, `urlCache = nil`) rather than `URLSession.shared`.
The provider serves the table `Cache-Control: public, max-age=…`, so the shared session would store a
second copy in the on-disk `URLCache` that deleting `currency-rates.json` doesn't touch.

Rates come from `CurrencyRateStore` (`Core/`, owned by `AppCore`), which reads
[Frankfurter](https://frankfurter.dev) — open source, no key, no account, no quota, rates blended
from 84 central banks. One `GET api.frankfurter.dev/v2/rates?base=USD`, ~1.4 KB gzipped. v2 answers
with one flat `{date, base, quote, rate}` row per pair rather than a keyed table, and omits the
base's own row — the store folds both into the `[code: rate]` shape `CurrencyRates` stores.

The table is cached at `~/Library/Caches/<bundle-id>/currency-rates.json`, refreshed every 24h with a
15-minute retry after a failure. The feed republishes about once a day, so a tighter interval would
cost requests without returning newer numbers. Age is measured from the persisted `fetchedAt`, not
from launch, so relaunching Tinycast never re-fetches a snapshot that is still fresh — a cold start
with a same-day cache makes zero requests. Offline, the last snapshot keeps answering; with no snapshot at all
the card says so rather than guessing, and a currency the feed doesn't quote reports
`No exchange rate for <CODE>.` The store hands `CalcEngine.evaluate` a finished `CurrencyRates`
value — the engine never fetches, which is what keeps it Foundation-only and testable. `CalcMemo`
keys its memo on the snapshot's `fetchedAt`, so a fresh table re-evaluates without diffing every rate.

Money rounds to two decimals (`CalcFormatter.currency`), widening to four significant digits below a
cent — in *plain* notation, deliberately not `%g`, so `1 IDR to USD` reads `0.00005539 USD` rather
than `5.539e-05`.

## Result and rendering

`CalcResult` carries an `expression` (left), a `display` / `copyText` payload (right), and optional
`sourceBadge` / `targetBadge` word-name pills. `CalculatorCard` renders it as a two-column card.

When the launcher or Calculator History query evaluates to a result the card is pinned at the top of
the list (flat selection index 0, shifting rows by one) and Enter copies the answer + records it to
`CalculatorHistoryStore`.
