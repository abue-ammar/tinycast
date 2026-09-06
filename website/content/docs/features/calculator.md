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
`1.5 hr`, answered in the _leading_ unit. Mixed quantities bind as one amount:
`5w * 3h 30min` means `5w * (3h 30min)`, and `90km / 1h 30min` gives `60 km/h`.

A bare number takes the unit written against it: `5kg+5` is `10 kg`, `$10 + 5` is `15.00 USD`.

Percentages are relative for `+` and `-` (`10kg + 20%` → `12 kg`) and a fractional scalar for `*` and
`/` (`10kg * 3%` → `0.3 kg`, `10kg / 25%` → `40 kg`).

A bare quantity auto-converts: `1m` gives feet and inches, `1hr` gives 60 min.

Measurements combine into area, volume, speed and other physical quantities:

| You type | You get |
| --- | --- |
| `5m * 4m` | `20 m²` |
| `2m * 3m * 4m to l` | `24,000 L` |
| `sqrt(25m2)` | `5 m` |
| `100km / 2h to km/h` | `50 km/h` |
| `90km/h * 20min to km` | `30 km` |
| `100km / 40km/h to duration` | `2 hr 30 min` |
| `1GB / 100mbps to s` | `80 s` |
| `1500w * 2h to kwh` | `3 kWh` |
| `1 / 20ms to hz` | `50 Hz` |

Derived results use base units unless you name a target with `to` / `in`.
Power × minutes/hours naturally uses Wh/kWh; current × minutes/hours uses Ah/mAh.
`m²` and `m2` mean square meters; `(2m)^2` squares the whole quantity.
Use `pi * (2m)^2` for a circle's area and `sin(30deg) * 10m` for a triangle's opposite side.

`to timespan` also works for mixed durations: `(1hr + 30min) to timespan` → `1 hr 30 min`.
Affine temperatures may only be added or subtracted within one scale; products involving
temperatures and unsupported dimensions remain errors.

## Volume and flow

| You type | You get |
| --- | --- |
| `1m3` | `1,000 L` |
| `1dm³ to l` | `1 L` |
| `2m * 30cm * 40cm to l` | `240 L` |
| `pi * (10cm)^2 * 30cm to l` | `9.424777961 L` (cylinder) |
| `500l / (2m * 1m) to cm` | `25 cm` (tank depth) |
| `10l / 2min to l/min` | `5 L/min` |
| `10l/min * 30s to l` | `5 L` |
| `150l / 10l/min to duration` | `15 min` |
| `60l/min to m3/h` | `3.6 m³/h` |

Cubic units accept `mm³`, `cm³`, `dm³`, `m³`, `in³`, `ft³`, and `yd³`, or a plain `3` instead of `³`.
Liquid measures include `mL`, `cL`, `dL`, `L`, cups, tablespoons, teaspoons and US gallons/quarts/pints.
Use `fl oz` / `floz` for US fluid ounces; plain `oz` is weight.
Flow units include `L/s`, `L/min`, `L/h`, `m³/s`, `m³/h`, and `gal/min` (`gpm`, US gallons per minute).

## Electrical calculations

| You type | You get |
| --- | --- |
| `5 watt * 3h 30min` | `17.5 Wh` |
| `5 watt * 3h 30min to kwh` | `0.0175 kWh` |
| `12V * 2A` | `24 W` |
| `12V / 6ohm` | `2 A` |
| `12V / 2A` | `6 Ω` |
| `500mA * 3h 30min` | `1,750 mAh` |
| `2000mAh / 500mA to hours` | `4 hr` |
| `12V * 2Ah to wh` | `24 Wh` |

Use `volt`, `amp`, `ohm`, `coulomb` or their listed symbols. Coulombs display as `As` (ampere seconds);
`C` continues to mean Celsius. SI mega symbols keep their case: `MW` is megawatts, `mW` is milliwatts.
For power and energy, use `W` and `Wh` respectively; they are different dimensions.

## Pixels and density

| You type | You get |
| --- | --- |
| `3000px / 300ppi to inches` | `10 in` |
| `5in * 300ppi` | `1,500 px` |
| `3000px / 10in to ppi` | `300 ppi` |
| `300ppi to px/cm` | `118.1102362 px/cm` |
| `sqrt((3840px)^2 + (2160px)^2) / 27in` | `163.1783089 ppi` |

Use `px`, `pixel` or `pixels`; density accepts `ppi`, `px/in`, `px/cm`, `px/mm` and `px/m`.
Pixels have no fixed physical size, so supply a density when converting to inches or centimeters.
The last example calculates a 27-inch, 3840×2160 display's density from its diagonal.

## Currency and crypto

| You type                    | It means                    |
| --------------------------- | --------------------------- |
| `1 euro to dollars`         | Named currencies            |
| `€20 to GBP` / `20€ to GBP` | Symbols, either side        |
| `eur to usd`                | Amount 1 implied            |
| `1 btc to eur`              | Crypto                      |
| `$10 + €5`                  | Mixed arithmetic            |
| `(20 sgd to usd) * 30`      | Convert, then multiply      |

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

Date and clock arithmetic:

| Grammar                | Example                             |
| ---------------------- | ----------------------------------- |
| Time until a moment    | `hrs till 9am`, `days till 9april`  |
| Time since a moment    | `days since 9jul`, `hrs since noon` |
| A moment ± a duration  | `next monday at 7:30 + 5`, `now + 90 min` |
| Mixed durations        | `tomorrow at 7:30 + 1 day 2h 15min` |
| Months and years       | `31.1.26 + 1 month`, `29.2.24 + 1 year` |
| Difference between two | `jul 4 - today`, `9:30 - 7:00 to minutes` |
| Duration from a moment | `3 days from next monday at 7:30`, `1.5 hours ago` |

`till` takes the next occurrence, `since` the most recent past one; an absolute date ignores the
bias. Plain fractions such as `5/2 - 1/2` stay arithmetic.

A bare offset means hours when the moment includes a clock, and days otherwise.
`next monday at 7:30 + 5` is Monday at 12:30 PM. Offsets chain left to right;
`+ 1h 30min - 15min` adds 75 minutes. Fractional hours/minutes work; calendar units require whole counts.

Month and year shifts follow the calendar: `31.1.26 + 1 month` lands on 28 February.
`+ 1 day` preserves the wall clock across daylight saving; `+ 24 hours` adds elapsed time.
Clock differences display a timespan or your chosen unit (`to hours`, `to minutes`, `in seconds`).
Bare clocks share today's date when subtracted: `7:30 - 13:30` is `-6 hr`.

`weekdays` / `business days` skip Saturday and Sunday in date arithmetic. Holidays are not counted.
As a standalone conversion unit, `workdays` means eight hours.

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
