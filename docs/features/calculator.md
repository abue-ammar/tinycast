# Inline calculator

`Features/Calculator/Model/` is a **Foundation-only** engine (no AppKit / SwiftUI imports) fronted by
`CalcMemo`, a one-deep memo mirroring `AppIndex`'s. It must stay Foundation-only because the
`Tests/calc-test.swift` harness compiles the real engine sources — including `CalcDateTime`. It is
also **pure**: the inputs it can't compute — the FX rate table and the Mac's own currency — are passed
in (see Currency below).

## Invariants

- **`Model/` (including `CalcDateTime`) stays Foundation-only *and pure*** — no AppKit or SwiftUI, no
  clock read, no network, **no `Locale`**. `calc-test` compiles the real engine sources. Every
  externally-sourced input is injected: the clock via `now`/`calendar`, the FX table via `rates`, and
  the Mac's own currency via `region`, which `RegionCurrency` reads and `CalcMemo` passes down.
- **`CalcEngine.evaluate` never fetches** — it takes a finished `CurrencyRates?`, nil meaning no
  snapshot has landed yet. `CurrencyRateStore` owns the fetch and the cacheless `.ephemeral` session,
  and `CurrencyFeed` — pure, so the harness covers it — turns the payloads into that snapshot.
- **The time-zone table is Foundation's, never generated and never hand-listed.**
  `TimeZone.knownTimeZoneIdentifiers` already carries the whole IANA database, so `CalcTimeZone`
  builds its city index from that on first use rather than shipping a copy that would rot every time
  IANA moves a zone. `TimeZone.abbreviationDictionary` stays deliberately unused — it holds 51
  entries and its `BDT` is the Bangladeshi taka. The home zone is read off the **injected calendar**,
  never `TimeZone.current`, which is what keeps the path pure and the harness deterministic.
  `localizedName` needs a `Locale`, so a badge is the identifier's own city component instead.
- **A workday is 8 hours, and nothing consults a calendar.** Weekends and public holidays would make
  the same query answer differently on two Macs, and the only supported source for them is EventKit,
  whose Full Calendar Access grant a calculator must never provoke mid-keystroke. `workdays` is
  therefore an ordinary time unit, and `calendarEnabled` stays the Calendar feature's own consent.
- **`CurrencyData.generated.swift` is emitted by `node Scripts/gen-currencies.js`** and never hand-edited.
  Three currency tables are hand-maintained, all in `CalcCurrency`: `contested`, the nouns several
  currencies share (`dollars`, `pounds`); `isoNames`, the standard's own names where CLDR substitutes
  a different one (ISO 4217 calls CNY "Yuan Renminbi"); and `crypto`, which no standards body names.
  Do not add slang or synonyms to any of them — no source of truth, so they rot.

## Evaluation pipeline

`CalcEngine.evaluate` runs:

1. Natural-language date/time (`CalcDateTime`, e.g. `hrs till 9am`, `days till 9april`,
   `today + 3 weeks`)
2. **Time zones** (`CalcTimeZone`, e.g. `time in Tokyo`, `5pm ldn in sf`) — before tokenizing,
   because a zone phrase is words rather than calculator input
3. Tokenize, then preserve the complete prefix of a trailing binary operator
4. Base conversion
5. **Typed quantity arithmetic** (`10kg + 500g`, `$10 + €5`, `5m * 4m`,
   `100km / 2h to km/h`, `(1hr + 30min) to timespan`)
6. Explicit unit conversion (`10km to mi`, `m to ft`, `day s`)
7. Currency conversion (`1 euro to dollars`, `€20 to GBP`, `1 btc to eur`)
8. Bare-unit auto-conversion (`1m` → feet + inches, `1hr` → 60 min)
9. Natural-language percent, ratio and list forms (`CalcPercent`)
10. Numeric reject, then plain arithmetic

Typed arithmetic precedes simple conversion so `1 / 20ms to hz` divides by a duration,
not a scalar subsequently labeled milliseconds. Simple conversions still own their source badges.

Date/time depends on the clock, so it takes an injected `now` / `calendar` — the public `evaluate(_:)`
uses the live clock, and `evaluate(_:now:calendar:)` lets `calc-test.swift` assert exact strings
against a fixed clock.

`CalcDateTime` recognizes these grammars:

- **A** — duration until a moment: `hrs till 9am`, `days till 9april`
- **B** — duration since a past moment: `days since 9jul`, `hrs since noon`
- **C** — a moment ± durations: `today + 3 weeks`, `now + 90 min`,
  `17.2.26 + 100 weekdays - 4 + 2`
- **D** — difference between two moments: `jul 4 - today`
- **E** — a leading duration: `5 weekdays from now`, `3 days from today`, `2 weeks ago`
- **F** — a weekday inside a future week: `monday in 3 weeks`, `friday in 2 weeks`
- **G** — a named moment, once qualified: `tomorrow at 9am`, `next monday`, `last friday`

**An answered moment badges its weekday.** Grammars C and E resolve to a date, and the day of the
week is the thing a date does not say out loud — so `5 weekdays from now` reads `4 September` under
a `Friday` pill rather than repeating the weekday inside the date and badging it `Result`.
`answerString` is `momentString` without the leading `EEEE` for exactly that reason; the source
badge keeps its own weekday, since nothing else on the card carries it.

A bare, recurring date or time resolves by _bias_: `till` takes the upcoming occurrence, `since` the
most recent past one; an absolute date ignores the bias. Grammar D needs an unambiguous date/time signal: a letter, a clock, an ISO or dotted date,
or an explicit time-unit target. Fraction-only operands (`5/2 - 1/2`) remain arithmetic. Two-digit years expand
the way date pickers do — 00–68 to the 2000s, 69–99 to the 1900s.

A **dotted** date is day-first (`19.2.27` is 19 February 2027), matching the convention that writes
it, where the slashed form stays month-first. It needs three parts and a two- or four-digit year,
which is what separates a date from a decimal and from a version number: `1.5 + 3` is 4.5 and
`1.2.3 + 1` earns no card.

The version-number overlap is only **partly** closed, and irreducibly so: `1.2.24` is both a
plausible semver and a valid 1 February 2024, with nothing in the text to tell them apart. A
one-digit or three-digit tail is rejected (`1.2.3`, `10.15.7`), which covers the common shapes, but
a two-digit patch reads as a date. Requiring a four-digit year would close it and cost `19.2.27`,
which is the more common thing to type.

The same convention writes an **ordinal dot** after the day, so `28. aug + 3` reads as 28 August.
Only a trailing dot is dropped, which is why `28.5 aug` stays silent rather than becoming a date.

Grammar G needs the qualifier. A lone `tomorrow` is an app search, so `at <time>` or a leading
`next` / `last` earns a card — the same rule that keeps `today` and `july` silent. **A written day
is qualifier enough**: `25. aug`, `aug 25` and `25.8.27` all answer, badged with their weekday,
because nobody types a day-and-month pair looking for an app. A month alone still names no day, so
`july` stays a search.

A bare date takes the year it is **nearest**, not the next one — three days behind is likelier the
date meant than the same day twelve months out. Grammar C shifts a moment, so it reads the year the
same way and `25. aug` and `25. aug + 3` can never disagree. Grammar D measures _to_ a moment,
where the documented forward bias still decides: `jul 4 - today` keeps looking ahead.

`parseMoment` owns `at <time>` for every grammar, so `next monday at 7:30 + 5`,
`hours till tomorrow at 7:30` and `3 days from next monday at 7:30` compose the same way.
The bias applies to the combined date and clock: after Friday midnight, `hours till friday at midnight`
advances a week while `hours since friday at midnight` uses today's midnight.
Explicit clock times survive day, month and year shifts. Invalid clock components and wall-clock times
that do not exist during a DST jump stay silent. Repeated fall-back times use Calendar's first occurrence.

Durations can combine (`1 day 2h 15min`) and use fractional hours/minutes when they resolve to whole
seconds (`1.5 hours`). Days, weeks, weekdays, months and years require whole counts. Months and years
use the injected Calendar, including end-of-month clamping: `31.1.26 + 1 month` is 28 February.
A calendar day preserves the wall clock across DST; 24 hours is elapsed time and may change it.
`ago` anchors sub-day durations to now and date-only durations to today.

Subtracting moments with clock times produces a timespan; `to hours` / `to minutes` / `in seconds`
selects an elapsed-time unit. Bare clocks in a difference share today's date, so `7:30 - 13:30`
is `-6 hr` even when one clock has already passed. Date-only differences retain calendar-day counting;
an explicit hours target measures elapsed time, so a DST day can be 23 or 25 hours.

A bare number after a moment takes the unit that moment implies: hours off a clock time
(`3:45pm + 5` → 8:45 PM), days off a date (`august 5 + 5` → 10 August). It is checked before the
spelled durations, since `5` names no unit of its own.

Grammar C **chains**: every `± <term>` after the first is applied in written order, so
`17.2.26 + 100 weekdays - 4 + 2` shifts three times. All of them must be durations — one term that
is not (`today + 3 weeks - kg`) drops the whole card rather than answering from a prefix, which is
what leaves a trailing moment to grammar D and keeps `jul 4 - today` a difference.

Grammar F resolves the weekday **inside the landing week** rather than counting forward from the
landing day, so `monday in 3 weeks` is that week's Monday whichever day you ask on. The week is
`Calendar`'s own, so it follows the user's first-weekday preference — on a Monday-first calendar
`sunday in 1 week` lands at the end of that week rather than its start. It runs after every other
grammar because `in` is also the unit connector, which is what keeps `10 in in cm` a conversion.

`CalcQuantity` is a separate typed precedence parser rather than a mode added to the scalar
`CalcParser`. Scalar `*` / `/` preserve the unit, compatible quantity division returns a scalar, and a
trailing `to` / `in` converts the complete expression. A conversion inside parentheses is itself a
quantity, so `(20 sgd to usd) * 30` converts then multiplies. Percentages keep relative semantics
for addition (`10kg + 20%` → `12 kg`) and act as fractional scalars for multiplication and division
(`10kg * 3%` → `0.3 kg`, `10kg / 25%` → `40 kg`).

A conversion may also appear **mid-expression, but only where `+` or `-` follows it**:
`10kg to lb + 3lb` converts and then adds, without needing the parentheses it used to. The
restriction is the whole point. `20 eur to usd * 30` has two honest readings — convert then scale,
or convert into a scaled unit — so it stays silent and keeps asking for `(20 eur to usd) * 30`,
while `+` and `-` carry no such ambiguity because a conversion target is never an addend.
A **trailing** `to` is untouched by this and still converts the whole expression, so
`10kg + 500g to lb` remains the sum in pounds rather than `10kg + (500g to lb)`.

**The last unit typed decides the answer's unit.** `+` / `-` convert the _left_ side into the right
operand's unit, so `5feet + 1m` is `2.524 m` and `10kg + 500g` is `10,500 g` — the unit you finished
writing is the one you were thinking in. Chains are left-associative, so `1kg + 500g + 2lb` ends in
pounds. A conversion suffix overrides it entirely (`10kg + 500g to lb`).

Adjacency is the exception. `5 feet 3 inches` and `1hr 30min` are one quantity in composite notation,
not a sum, so they answer in the _leading_ unit (`5.25 ft`, `1.5 hr`). `QuantityParser.peekBinary`
distinguishes the two — it reports `consumesToken: false` for the invisible `+` between adjacent
quantities — and `addOrSubtract` keys the unit choice off exactly that flag. Composite notation binds
above multiplication, division and powers: `5w * 3h 30min` means `5w * (3h 30min)`, and
`90km / 1h 30min` divides by the entire 90-minute duration. An explicit `+` keeps additive precedence.

A bare number takes the unit it is written against: `5kg+5` is `10 kg`, `$10 + 5` is `15.00 USD`. Under
adjacency the same input stays silent, because there a bare trailing number is a unit still being
typed — `1hr 30` is one keystroke short of `1hr 30min`, and answering `31 hr` would be worse than
answering nothing.

Once an operator is involved the answer stays in the units written, so `2 * 5kg` is `10 kg`. Only a
bare quantity (`50cm`, `1m`) falls through to the keyword-less auto-conversion below.

`CalcDimension` records length, mass, time, data, electric-current, pixel and currency exponents. Products add exponents, division
subtracts them, and powers multiply them. `CalcUnits.baseUnits` resolves supported results back to
ordinary units, so conversions and addition need no second representation. Derived results use base
units unless a trailing conversion names another: `5m * 4m` → `20 m²`,
`100km / 2h to km/h` → `50 km/h`, `90km/h * 20min to km` → `30 km`.
Area, volume, volume flow, speed, acceleration, force, pressure, energy, power, frequency, data rates
and electrical and pixel units compose through this same path. `CalcUnitExpression` composes other
dimensions from existing units, retaining their factors and symbols: `2kg / 4m3` → `0.5 kg/m³`,
`1kg/m3 to g/cm3` → `0.001 g/cm³`. Temperature and angle stay outside compound products.

All factors share composable bases: cubic meters for volume and bytes per second for data rates.
To add a dimension, declare its signature on `UnitCategory`, add its units to `byName`, and register
one output in `baseUnits`. A new unit within a category only needs a table entry.
`m²` / `m2` and `m³` / `m3` name units; `(2m)^2` squares the entire quantity.
`CalcUnits.productUnit` selects Wh/kWh for power multiplied by a minutes-or-larger time unit,
and Ah/mAh for current multiplied by one; other derived products retain their base unit.
Explicit conversion still overrides the selection. Electrical relations use the same dimensions:
`12V * 2A` → `24 W`, `12V / 6ohm` → `2 A`, `12V / 2A` → `6 Ω`,
`500mA * 3h 30min` → `1,750 mAh`, `12V * 2Ah to wh` → `24 Wh`.
Charge's base symbol is `As` (ampere seconds), also named `coulomb`; `C` remains Celsius.

Identifiers check exact registered spellings before case folding, so SI mega symbols (`MW`, `MΩ`,
`MA`, `MV`, `MWh`, `MAh`) remain distinct from milli symbols. Spelled names remain case-insensitive.
The typed parser shares scalar constants and functions with `CalcParser`; `pi * (2m)^2`,
`sqrt(25m2)` and `cbrt(8m3)` work without a geometry-specific grammar.

Volume includes cubic millimeters through cubic meters, cubic inches/feet/yards, and mL/cL/dL/L.
Bare cubic amounts auto-convert to liters or milliliters. Customary volumes use US liquid measures,
including `fl oz` / `floz`; plain `oz` remains weight.
Volume flow adds length³/time to the same dimension table, with `m³/s` as its base:
`10l / 2min to l/min` → `5 L/min`, `10l/min * 30s to l` → `5 L`,
`150l / 10l/min to duration` → `15 min`. Its units also include L/s, L/h, m³/h and gal/min (`gpm`).

Pixels have their own dimension, so `3000px to cm` cannot assume a physical size.
An explicit density supplies it: `3000px / 300ppi to inches` → `10 in`,
`5in * 300ppi` → `1,500 px`, and `3000px / 10in` → `300 ppi`.
Density defaults to `ppi` (also `px/in`); `px/cm`, `px/mm` and `px/m` are conversion targets.
Square pixels (`px²` / `px2`) let the ordinary powers and roots calculate a display's diagonal:
`sqrt((3840px)^2 + (2160px)^2) / 27in` → `163.1783089 ppi`.
These are image pixels, not CSS's fixed reference pixels or printer dots.

`to timespan` / `to duration` formats any evaluated time quantity, including
`(1hr + 30min) to timespan` and `100km / 40km/h to duration`. It uses the typed parser directly.
Affine temperatures may only be added or subtracted when both operands use the same scale; treating
an absolute Celsius/Fahrenheit value as a delta would silently produce physically incorrect answers.

Errors are reserved for input that can only be a mistake — two incompatible units (`1kg + 1m`), or a
unit against a currency. Everything else that cannot be evaluated stays silent rather than flashing a
card mid-keystroke.

An attached `k` is a thousands suffix (`10k` → `10,000`), while whitespace keeps Kelvin explicit
(`10 k to c`); the established attached Kelvin conversion form remains valid when the temperature
target makes the intent unambiguous (`273.15K to C`).

A **compound unit** (`km/h`, `m³/h`, `mbit/s`, `fl oz`) stays whole only when the table knows its
spelling: the tokenizer looks ahead across `/` or whitespace between two alphanumeric runs,
folds superscript powers, and keeps them together only if `CalcUnits.byName` resolves the result.
The identifier's first scan supplies the currency prefix and compound-unit head without rescanning it.
That is the same table-consulting lookahead the `USD1K` prefix split already uses, and it is why `6/2(1+2)` and
`10 m / 2` still divide while `1 km/x` stays silent.

Beyond the core four, `CalcParser.functions` carries the reciprocal trig (`cot`, `sec`, `csc`),
the inverses (`asin`/`arcsin` through `atan`), the hyperbolics (`sinh`, `acosh`, …) and
`cbrt`/`exp`/`log2`/`sign`/`trunc`, alongside the `tau` and `phi` constants. `sec` is also the
abbreviation for seconds, which costs nothing: a unit position resolves through `CalcUnits` long
before a bare name reaches the function table, so `10 sec to min` stays a duration.

Scientific notation (`1e5` → `100,000`, `5e-3km`, `3e+2`) is read only while the exponent hugs the
mantissa, which is what keeps `2 e` and `2e` reading as 2 × Euler's _e_ — an exponent needs digits
after the `e`. Like `10k`, it tokenizes as a shorthand rather than a plain literal, so a lone `1e5`
still earns a card where a lone `100000` deliberately doesn't. A literal that overflows to infinity
(`1e400`) is treated as non-calculator input, not as a card.

## Time zones

`CalcTimeZone` answers `time in Tokyo`, `what time is it in London`, `5pm ldn in sf` and
`9:30am in nyc`. It runs **before the tokenizer** — a zone phrase is words, and `5pm ldn in sf`
is not calculator input — but its grammar always needs an `in` / `to` / `at` connector, so an
ordinary app search never reaches the zone table at all.

The source is the Mac's own zone unless the query names one, which is what makes `5pm london in sf`
work without either side being local. That zone comes from the **injected calendar**, so `Model/`
performs no environment read and `calc-test` pins UTC exactly as it pins the clock. A result that
lands on another date is suffixed `(tomorrow)` / `(yesterday)` rather than silently reading as the
same day — the copyable text stays the bare time.

A trailing `+ 2h` / `- 30 min` shifts the answer before it is converted, so `5pm ldn in sf + 2h`
stays one query rather than needing two. Only sub-day units qualify, since a zone answer is a clock
time, and `5pm london in sf + 2 kg` is silent rather than wrong.

The offset's unit may be left out — `time in sao paulo + 5` is five hours — because a clock answer
admits no other reading. The implication is the **offset's alone**: `time in 4` still names no zone
and stays silent, and a bare `5 + 3` is arithmetic exactly as it was. It mirrors the bare number a
moment already takes in grammar C.

`diff paris` answers how far a zone runs from the Mac's own, and a duration may stand where a zone
would (`time in 4 hours`, `time in 4 hours in san francisco`) — the zone table is tried first, so a
city always outranks a duration. City names are matched **diacritic-folded**, because the identifiers
carry no accents while the cities do: `são paulo` and `zürich` resolve alongside their bare
spellings, the same folding `CalcCurrency` already applies to its nouns.

Two tables back it. `cities` is derived from `TimeZone.knownTimeZoneIdentifiers` on first use: 443
identifiers keyed by their city component, ~0.8 ms to build and ~18 ns to query, so nothing is
generated and no copy of tzdata is committed. `aliases` is the hand-written half, and the only place
judgement lives — the abbreviations (`pst`, `cet`, `jst`), the nicknames a zone name doesn't carry
(`sf`, `nyc`, `ldn`), and the renamed zones Foundation still resolves but no longer lists
(`kolkata`, `saigon`). It is deliberately small and deliberately not slang, for the same reason
`CalcCurrency` refuses `quid`.

It also carries the **cities IANA never names**. The database ships one representative city per
distinct clock history, not one per city, so Graz, Salzburg, Hannover and Basel simply do not exist
in it — their clocks have never differed from Vienna's, Berlin's or Zurich's by a second. Roughly a
hundred are listed, chosen as the ones people actually type. Accented spellings need no entry of
their own, since the lookup folds diacritics before it reaches the table.

Apple can resolve any city: `MKGeocodingRequest` returns a `TimeZone` directly, needs no
entitlement and prompts for nothing. It is deliberately **not** used. It is asynchronous and
network-backed at ~150 ms a call, where `CalcEngine.evaluate` is synchronous and runs against every
keystroke behind a one-deep memo — so `time in salzburg` would issue a request per prefix typed, and
answer nothing at all offline. A launcher that answers `time in vienna` on a plane but not
`time in salzburg` is worse than one with a known edge.

`aliases` also carries the **IATA airport codes** (`vie`, `lhr`, `nrt`, `sfo`), which no Foundation
surface knows: `TimeZone(abbreviation:)` and `TimeZone(identifier:)` both return nil for every one,
and the whole `abbreviationDictionary` is 51 zone abbreviations rather than airports. They are a
curated product choice, so the list is the busiest airports rather than an attempt at all ~9,000.
Two are deliberately absent: `MAD` is the Moroccan dirham, and `IST` is India Standard Time — a
currency and a zone abbreviation both outrank an airport, the same ordering the rest of the file
follows. The compiler enforces the rest: a duplicate key in the literal is a warning, which is what
caught `syd` and `hkg` already being nicknames.

Order settles the collisions. Time zones run **last** among the named paths, after units and
currency, so `10 cordoba to usd` stays money and `1 cup to ml` stays volume. `cordoba` is the one
word the zone and currency tables both claim.

## Timespans

`145 mins to timespan` breaks a duration into the units that fit it (`2 hr 25 min`), with zero
parts dropped. Weeks are the largest step on purpose: a month is not a fixed number of seconds, so
carrying one would make the answer depend on which month you meant. Only a time unit converts, so
`10 km to timespan` stays silent.

## Workdays

`workdays` has two meanings; neither reads the user's calendar events.

As a **unit** it is 8 hours, which answers `55h in workdays` and `3 workdays in hours`.

As a **duration in date arithmetic** it counts days and skips weekends: `today + 5 business days`,
`tomorrow + 10 work days`, `5 weekdays from now`, `august 26 2026 + 15 workdays`. `business day`,
`work day`, `working day` and `weekday` are all the same phrase, written as one word or two.
`addBusinessDays` aligns a weekend anchor first, jumps whole five-day workweeks as seven calendar
days, then walks only the remainder. Work stays bounded even at the 10,000-day limit, in either
direction; `saturday + 1 business day` still lands on Monday.

Public holidays are deliberately not modelled in either. The only supported source is EventKit, and a
calculator must never provoke its Full Calendar Access grant mid-keystroke — see the invariant above.

## Implicit multiplication

Juxtaposition means `*` at the same binding power as an explicit one (`4(2+3)` → 20, `2pi`,
`2sqrt(9)`, `(2+3)(2+3)`), so it binds tighter than `+` and looser than `^`, and `6/2(1+2)` agrees
with `6/2*(1+2)`. `CalcParser.parseExpression` checks it after `peekBinary()` fails and, unlike a real
operator, consumes no token before parsing the right operand.

Only `(` or a name in `CalcParser.constants` / `functions` starts an implicit product. Adjacent _numbers_ never do — `5 3` stays an app search — and no unit or
currency name is a constant or function, so `10km` keeps its own path. `QuantityParser.peekBinary`
carries the same rule so the typed side agrees (`$5(2)` → `10.00 USD`, `2(3)kg` → `6 kg`, matching
`2*(3)kg`); adjacency there still means the composite-quantity `+` described above, never a product.

## Natural-language forms

`CalcPercent` owns the phrasings the arithmetic parser can't see, all of which run after the unit
and currency paths so a spelled-out word never outranks a measurement:

- `20% off 500` → 400, and `50 as % of 200` → 25%
- `15% tip on 42` → 6.3 — the tip alone, which is what the phrase asks for
- `50 is what % of 200` → 25%, the spoken form of `as % of`
- `30 is 20% of what` → 150, solving for the whole instead of the share
- `ratio of 1920 to 1080` → `16 : 9`, reduced by GCD; integers only
- `average|sum|min|max of 10, 20, 30`, separated by `,` or `and`
- `round 47 to nearest 5` → 45, snapping to a step rather than a digit count

`CalcToken.comma` separates these lists and function arguments. Outside function parentheses,
a comma **between digits** remains a grouping separator, so `1,000 + 234` is unchanged and a bare
`10,5` stays silent.

Each of these badges what its number **is** — `Tip`, `Discounted`, `Percentage`, `Total`, `Ratio`,
`Average`, `Sum`, `Minimum`, `Maximum`, `Rounded` — rather than the bare `Result` that says nothing
the card doesn't already show. `min` and `max` are only told apart by it.

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

The table is **generated except for the judgement calls**. `node Scripts/gen-currencies.js` joins three
sources on the ISO code and emits `CurrencyData.generated.swift`:

- **The fiat rate feed** decides which currencies exist — the same feed the rates come from, so the
  table can never list something the app can't price.
- **CLDR's supplemental currency data** decides which of those are still spent. The feed carries no
  retirement metadata and happily quotes codes their countries abandoned years ago, so a code CLDR
  marks live in some region is kept, a code CLDR retired everywhere is dropped, and a code CLDR never
  mentions is also kept — absence of evidence is not retirement, and that distinction is what
  preserves `CNH`, the metals, `XDR` and the Crown Dependencies' pounds, none of which are any
  region's tender. 159 codes survive.
- **CLDR** (`en`) decides what humans call them: display name, currency sign, singular/plural noun.
  Read from the pinned `cldr-json` checkout, not the host's `Intl`, whose output shifts with the
  local ICU version.

Only _unambiguous_ CLDR data is emitted — 26 signs and 130 nouns. CLDR itself supplies the sign
tie-break: it writes every dollar but USD as `CA$`/`A$`/`NT$`, so plain `$` is claimed by exactly one
currency. Bare Latin letters CLDR lists as symbols (`P` for BWP, `L` for HNL) are dropped, since a
letter is indistinguishable from a word to the tokenizer. Accented nouns are emitted both as written
and folded, so `krónur` and `kronur` both resolve. The noun itself is the name's last word, which is
only wrong where that word isn't one — `NOT_NOUNS` in the generator drops those ("Special Drawing
Rights" is not a "rights").

What's left hand-written in `CalcCurrency.swift` starts with `contested`: the nouns several
currencies share, where CLDR correctly refuses to choose and the calculator must. `dollars` is
claimed by 22 currencies, `francs` 10, `pounds` 9, `pesos` 8, `rupees` 6. CLDR says "US dollars" and
"Canadian dollars"; nothing in it says a bare "dollars" is USD. Words that stay genuinely ambiguous
are assigned to nobody — `krona` is both SEK and ISK, so it produces no card. Slang and synonyms
(`quid`, `bucks`) are deliberately _not_ carried: they'd be hand-maintained data with no source of
truth. `isoNames` is the narrow exception that proves the rule: where ISO 4217 itself names a
currency and CLDR substitutes a different word, the standard's name is carried with the standard as
its source — CNY is "Yuan Renminbi" to ISO 4217, so `rmb` and `renminbi` resolve, while CLDR's own
"Chinese Yuan" supplies `yuan` through the generator.

### Crypto

`CalcCurrency.crypto` is the third hand-written table, and the only one with no external source at
all: no standards body names a coin, and the feed silently omits any symbol it can't price, so it
can't even report which exist. The list is therefore a product choice — and it is also the symbol
list the fetch asks for, since `CurrencyRateStore` builds its request from `cryptoCodes`. The two
cannot drift apart. A symbol the feed drops reports `No exchange rate for <CODE>.`, exactly like an
unquoted fiat code, and starts working again on its own if the feed picks it back up.

Coins join the same `byName` table as `CurrencyDef`s, so every existing path — the sign tokenizer,
the `BTC1K` prefix split, `parseConversion`, typed arithmetic — works on them unchanged. They are
inserted **after** the generated nouns, so a ticker outranks one: `1 sol` is Solana while `soles` and
`pen` still reach the Peruvian sol. That is the only word the two tables both claim.

Order is the whole disambiguation story. Currency runs **after** the unit path, so a query both sides
of which are compatible units stays a measurement: `10 pounds to kg` is weight, `10 pounds to euros`
is money, and `1 cup to ml` stays volume even though `CUP` is the Cuban peso. A currency on one side
and a unit on the other produces the same friendly category error as any other mismatch
(`Cannot convert Currency to Weight.`).

The typed quantity path uses the same ordering and injected rate snapshot. Currency arithmetic is
therefore deterministic: `$10 + €5` converts the left operand into euros when rates are available —
the same last-unit-typed rule the measurements follow. Bare prefix and suffix signs (`$10`, `10$`)
are accepted, and a conversion suffix applies to the whole expression. Parentheses make the
conversion an operand (`(20 sgd to usd) * 30`), matching a trailing suffix on a scalar product
(`20 sgd * 30 to usd`).

### The Mac's own currency

An amount with no target answers in the region currency: on a machine set to Bangladesh, `1 usd`
reads `122.84 BDT`, badged `US Dollar → Bangladeshi Taka`, and `1 btc` follows the same rule. The
region comes from `RegionCurrency`, one `Locale.current.currency` read — a preference, so nothing
ever asks for location, and a `Model/` file never performs it.

Where the region names the currency already written, the amount pairs with the **dollar** instead —
the **euro** where the dollar is the one that was typed. Converting is the only reason to write a
lone amount, so `25 eur` on a European Mac answering `25.00 EUR` said nothing at all; it now reads
`28.95 USD`, which is what Raycast answers for the same query.

The target only applies where there is genuinely nothing else to say. An operator keeps the currency
written (`$10 + €5` stays euros), an explicit target overrides everything, a trailing operator holds
the typed currency while the expression is still being written (`$10 +`), and a lone code with no
amount is still an app search. Where the region names no currency, names one the table doesn't carry,
or names one the snapshot doesn't quote, the amount answers in the currency written rather than
erroring about a code the user never typed — an unresolvable region still names no target.

### Exchange rates

The fetch runs on a private **cacheless** `URLSession` (`.ephemeral`, `urlCache = nil`) rather than
`URLSession.shared`, so `currency-rates.json` stays the only copy on disk. The feed serves the table
`Cache-Control: public, max-age=…`, so the shared session would keep a second copy in the on-disk
`URLCache` that deleting the snapshot doesn't touch.

Rates come from `CurrencyRateStore` (`Calculator/Service/`, owned by `AppCore`), which issues two
requests concurrently: the fiat table, keyed `<base><code>` with the base's own row omitted, and the
coin table, which quotes the **inverse** — one coin priced in the base. `CurrencyFeed` folds both
into the single units-per-base map `CurrencyRates` stores, inverting the coins on the way in and
merging them last so a symbol both feeds quote takes the coin feed's own price. One flat table means
`convert(_:from:to:)` cross-rates fiat against crypto with no special case anywhere downstream.

The fiat half is required; the coins are best-effort. A run that misses them still answers for the
session but is **not** written to disk, and retries in **30 minutes** rather than waiting out the day.
Both halves of that follow from the store scheduling off the newest _whole_ snapshot rather than off
whatever `rates` currently holds: a partial one answers without resetting the clock, so it can neither
park the loop for a day nor be reloaded at launch as though it were complete.

The same rule absorbs a cached snapshot written before crypto existed. It still prices fiat, so it is
served rather than discarded — but it counts as no age at all, so the store re-fetches immediately
instead of trusting a `fetchedAt` that says the table is hours fresh. `CurrencyFeed.pricesCoins` is
that test, and it is sound only because a partial snapshot is never persisted.

The table is cached at `~/Library/Caches/<bundle-id>/currency-rates.json` and refreshed every 24h.
The feed republishes about once a day, so a tighter interval would cost requests without returning
newer numbers. Age is measured from the persisted `fetchedAt`, not from launch, so relaunching
Tinycast never re-fetches a snapshot that is still fresh — a cold start with a same-day cache makes
zero requests. Offline, the last snapshot keeps answering; with no snapshot at all the card says so
rather than guessing, and a currency the feed doesn't quote reports `No exchange rate for <CODE>.`
The store hands `CalcEngine.evaluate` a finished `CurrencyRates` value — the engine never fetches,
which is what keeps it Foundation-only and testable. `CalcMemo` keys its memo on the snapshot's
`fetchedAt` and the region currency, so either changing re-evaluates without diffing every rate.

Money rounds to two decimals (`CalcFormatter.currency`), widening to four significant digits below a
cent — in _plain_ notation, deliberately not `%g`, so `1 IDR to USD` reads `0.00005539 USD` rather
than `5.539e-05`.

## Result and rendering

`CalcResult` carries an `expression` (left), a `display` / `copyText` payload (right), and optional
`sourceBadge` / `targetBadge` word-name pills. `CalculatorCard` renders it as a two-column card.
`Payload.number` rounds once, then groups that text for display; unit and percent suffixes share it.
Date answers that display and copy identically also reuse their formatted text.

When the launcher or Calculator History query evaluates to a result the card is pinned at the top of
the list (flat selection index 0, shifting rows by one) and Enter copies the answer + records it to
`CalculatorHistoryStore`.

## Additional units and transfer rates

`MB/s` means megabytes per second; `Mbps` means megabits per second.
`100Mbps to MB/s` gives `12.5 MB/s`, and `1GB / 10MB/s to s` gives `100 s`.
Binary rates such as `MiB/s` and bit amounts such as `kbit` also work.
SI prefixes expand for meters, grams, seconds, hertz, newtons, joules, watts and pascals,
including `um`, `nm`, `us`, `ns` and `GHz`. Existing aliases keep their meanings.

Other units include tonnes (`t`), stone (`st`), nautical miles (`nmi`), mechanical horsepower (`hp`),
BTU (international table), `rpm`, pound-force (`lbf`), US/UK tons and UK liquid measures
(`ukgal`, `ukqt`, `ukpint`, `ukfloz`). Plain gallons and pints remain US measures.

## Functions and comparisons

Functions accept comma-separated arguments: `hypot(3,4)`, `round(3.14159,2)`, `log(8,2)`,
`gcd(12,18)`, `lcm(4,6)`, `atan2(1,1)`, `pow(2,10)` and `root(-8,3)`.
A one-argument `log` remains base 10. `min`, `max`, `sum`, `avg`, `mean` and `average` accept lists,
including compatible measurements: `sum(1km,500m)` gives `1.5 km`, and `hypot(3m,400cm)` gives `5 m`.
`round(2.567km,1)` keeps the unit. Inside function arguments, commas separate values;
write `1000` rather than `1,000` there.

`==`, `!=`, `<`, `<=`, `>` and `>=` compare numbers or compatible measurements and return booleans.
`1km == 1000m` is `true`; incompatible dimensions produce an error. Chained comparisons are rejected.
Integer operands support `&`, `|`, `xor`, `~`, `<<` and `>>`; `^` remains exponentiation.
Shifts require counts from 0 through 63. Bitwise operations, `gcd` and `lcm` require integers
strictly between −2⁵³ and 2⁵³, including their results; larger values and fractions are rejected.


## Compound prices and timestamps

`100 USD / 4hr` gives `25 USD/hr`; multiplying by `8hr` gives `200.00 USD`.
Compound targets work too: `25 USD/hr to EUR/min`. Arithmetic within one currency rate needs no
exchange snapshot; changing currency uses the same injected rates as ordinary money conversions.
A compound quantity can carry one currency factor or its reciprocal, but not currency squared.

`now to unix` returns whole Unix seconds; `now to unix ms` returns whole milliseconds.
`unix 0 to date` and `1000 unix ms` convert back to a local date/time.
RFC 3339 input accepts an explicit `Z` or `±HH:MM` offset and optional fractional seconds:
`2026-07-24T07:30:00+02:00 + 30min`, or `1970-01-01T01:00:00+01:00 to unix` → `0`.
Dates use the local calendar for display and arithmetic. Impossible dates, leap seconds and trailing
text are rejected; timestamp output rounds down to the requested unit and copies every integer digit.
