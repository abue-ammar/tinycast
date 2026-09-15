---
title: Calculator
description: Math, units, live currency and crypto, dates and time zones, answered inline as you type.
---

Type a calculation into the launcher and the answer appears on a card above the results. There is no
mode to switch into. It works it out as you type.

| Action           | Shortcut                                  |
| ---------------- | ----------------------------------------- |
| Copy Answer      | <kbd>return</kbd>                         |
| Copy Calculation | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>return</kbd> |

Copying the answer also saves it to **Calculator History**.

A plain word never gets a card. `tomorrow`, `july` or `pi` on its own is a search, not a sum.

## Arithmetic

`4(2+3)` is 20. `2pi`, `2sqrt(9)` and `(2+3)(2+3)` all work, and `6/2(1+2)` agrees with
`6/2*(1+2)`. A lone `x` between numbers multiplies too, so `3x3` and `$5 x 2` work. Two bare numbers
side by side never multiply, so `5 3` stays a search.

`mod` is spelled out rather than `%`, because `%` already means percent. It sits with multiply and
divide, and keeps the sign of the first number: `-10 mod 3` is `-1`.

`10k` is `10,000`. Scientific notation works (`1e5`, `5e-3km`, `3e+2`), while `2e` and `2 e` stay
2 × Euler's _e_.

Spoken roots accept measurements: `square root of 25m2` is `5 m`.

**A trailing operator keeps the last answer on screen.** `10 +` shows `10`, and `10kg + 500g +`
shows `10,500 g`, so the card does not flicker while you type the next number.

## Units

**The last unit you typed decides the answer's unit.**

| You type            | You get                                      |
| ------------------- | -------------------------------------------- |
| `5feet + 1m`        | `2.524 m`                                    |
| `10kg + 500g`       | `10,500 g`                                   |
| `1kg + 500g + 2lb`  | pounds                                       |
| `10kg + 500g to lb` | pounds; a trailing `to` overrides everything |
| `10kg to lb + 3lb`  | converts, then adds                          |

**Units side by side are one amount, not a sum.** `5 feet 3 inches` is `5.25 ft` and `1hr 30min` is
`1.5 hr`, answered in the _first_ unit. They bind together first, so `5w * 3h 30min` means
`5w * (3h 30min)`, and `90km / 1h 30min` gives `60 km/h`.

A bare number takes the unit next to it: `5kg+5` is `10 kg`, and `$10 + 5` is `15.00 USD`.

Percentages are relative for `+` and `-` (`10kg + 20%` is `12 kg`) and a plain share for `*` and `/`
(`10kg * 3%` is `0.3 kg`, `10kg / 25%` is `40 kg`).

A unit on its own converts to something useful: `1m` gives feet and inches, `1hr` gives 60 min.

Measurements combine into area, volume, speed and more:

| You type                     | You get       |
| ---------------------------- | ------------- |
| `5m * 4m`                    | `20 m²`       |
| `2m * 3m * 4m to l`          | `24,000 L`    |
| `sqrt(25m2)`                 | `5 m`         |
| `cube root of -8m3`          | `-2 m`        |
| `100km / 2h to km/h`         | `50 km/h`     |
| `90km/h * 20min to km`       | `30 km`       |
| `100km / 40km/h to duration` | `2 hr 30 min` |
| `1GB / 100mbps to s`         | `80 s`        |
| `1500w * 2h to kwh`          | `3 kWh`       |
| `1 / 20ms to hz`             | `50 Hz`       |

Results use base units unless you name one with `to` or `in`. Power times minutes or hours gives Wh
or kWh; current times minutes or hours gives Ah or mAh. `m²` and `m2` both mean square meters, while
`(2m)^2` squares the whole amount. Use `pi * (2m)^2` for a circle's area.

`to timespan` breaks a duration into parts: `145 mins to timespan` is `2 hr 25 min`. Weeks are the
biggest step, because a month is not a fixed length.

Temperatures can only be added or subtracted within one scale. Other units combine freely:
`2kg / 4m3` is `0.5 kg/m³`, and `1kg/m3 to g/cm3` is `0.001 g/cm³`.

## Volume and flow

| You type                     | You get                    |
| ---------------------------- | -------------------------- |
| `1m3`                        | `1,000 L`                  |
| `2m * 30cm * 40cm to l`      | `240 L`                    |
| `pi * (10cm)^2 * 30cm to l`  | `9.424777961 L` (cylinder) |
| `500l / (2m * 1m) to cm`     | `25 cm` (tank depth)       |
| `10l / 2min to l/min`        | `5 L/min`                  |
| `150l / 10l/min to duration` | `15 min`                   |
| `60l/min to m3/h`            | `3.6 m³/h`                 |

Cubic units accept `mm³` through `m³`, plus `in³`, `ft³` and `yd³`, or a plain `3` instead of `³`.
Liquid measures include mL, cL, dL, L, cups, tablespoons, teaspoons and US gallons, quarts and pints.
Use `fl oz` for fluid ounces; plain `oz` is weight. UK measures are `ukgal`, `ukqt`, `ukpint` and
`ukfloz`.

## Electrical

| You type                   | You get      |
| -------------------------- | ------------ |
| `5 watt * 3h 30min to kwh` | `0.0175 kWh` |
| `12V * 2A`                 | `24 W`       |
| `12V / 6ohm`               | `2 A`        |
| `12V / 2A`                 | `6 Ω`        |
| `500mA * 3h 30min`         | `1,750 mAh`  |
| `2000mAh / 500mA to hours` | `4 hr`       |

`C` means Celsius, so coulombs show as `As`. Case matters for mega and milli: `MW` is megawatts and
`mW` is milliwatts.

## Pixels and density

| You type                               | You get           |
| -------------------------------------- | ----------------- |
| `3000px / 300ppi to inches`            | `10 in`           |
| `5in * 300ppi`                         | `1,500 px`        |
| `3000px / 10in to ppi`                 | `300 ppi`         |
| `sqrt((3840px)^2 + (2160px)^2) / 27in` | `163.1783089 ppi` |

Pixels have no fixed size, so give a density to convert to inches or centimeters. The last example
works out a 27-inch 4K display's density from its diagonal.

### REM and EM

| You type      | You get   |
| ------------- | --------- |
| `24px`        | `1.5 rem` |
| `2rem`        | `32 px`   |
| `16px to rem` | `1 rem`   |
| `1rem + 8px`  | `24 px`   |

`rem` and `em` use the browser's default 16px root font size. `pt` means pints, not points.

## Data and transfer rates

`MB/s` is megabytes per second and `Mbps` is megabits per second. `100Mbps to MB/s` is `12.5 MB/s`.
Binary units like `MiB/s` and bit amounts like `kbit` work too.

Other units include tonnes (`t`), stone (`st`), nautical miles (`nmi`), horsepower (`hp`), BTU,
`rpm` and pound-force (`lbf`).

## Currency and crypto

| You type                    | It means                   |
| --------------------------- | -------------------------- |
| `1 euro to dollars`         | Named currencies           |
| `€20 to GBP` / `20€ to GBP` | Symbols, either side       |
| `eur to usd`                | An amount of 1             |
| `1 btc to eur`              | Crypto                     |
| `$10 + €5`                  | Mixed arithmetic           |
| `(20 sgd to usd) * 30`      | Convert, then multiply     |
| `100 USD / 4hr`             | `25 USD/hr`                |
| `25 USD/hr to EUR/min`      | A rate in another currency |

159 currencies, plus a hand-picked list of crypto.

**An amount on its own answers in your Mac's currency.** On a Mac set to Bangladesh, `1 usd` reads
`122.84 BDT`. If you type your own currency, it answers in US dollars instead, or in euros when you
typed dollars, since converting is the only reason to type a lone amount. This comes from your
region setting. **Nothing ever asks for your location.**

### Words with two meanings

Shared words are assigned on purpose: `dollars` could be 22 currencies, `francs` 10, `pounds` 9,
`pesos` 8 and `rupees` 6. A word that stays truly ambiguous gets **no card at all**. `krona` is both
Swedish and Icelandic, so Tinycast will not guess.

Slang does not work: **`quid` and `bucks` get no card.** `rmb` and `renminbi` do, because the ISO
4217 standard itself calls the currency "Yuan Renminbi".

Units come before money, so `10 pounds to kg` is weight, `10 pounds to euros` is money, and
`1 cup to ml` stays volume even though `CUP` is the Cuban peso. A crypto ticker wins over a word:
`1 sol` is Solana, while `soles` reaches the Peruvian sol.

### Rates

Rates are saved on your Mac and refreshed every 24 hours, counted from when they were saved.
Restarting Tinycast never fetches again early, so opening it with a fresh copy makes **zero**
network requests.

Crypto is best effort. If coin prices fail to load, money still works and coins try again in 30
minutes.

Offline, the last saved rates keep working. With none saved, the card says so instead of guessing. A
currency with no rate says `No exchange rate for <CODE>.`

Money rounds to two decimals, or four significant digits below a cent, always written out in full:
`1 IDR to USD` is `0.00005539 USD`, never `5.539e-05`.

## Dates and times

| What you want             | Example                                          |
| ------------------------- | ------------------------------------------------ |
| Time until a moment       | `hrs till 9am`, `days till 9april`               |
| Time since a moment       | `days since 9jul`, `hrs since noon`              |
| A moment plus or minus    | `today + 3 weeks`, `now + 90 min`                |
| A chain of shifts         | `17.2.26 + 100 weekdays - 4 + 2`                 |
| Months and years          | `31.1.26 + 1 month`, `29.2.24 + 1 year`          |
| The gap between two       | `jul 4 - today`, `9:30 - 7:00 to minutes`        |
| From or before a moment   | `3 days from next monday at 7:30`, `2 weeks ago` |
| A weekday in a later week | `monday in 3 weeks`, `friday in 2 weeks`         |
| A named moment            | `tomorrow at 9am`, `next monday`, `aug 25`       |

**An answer that is a date shows its weekday**, because that is what a date does not tell you out
loud.

`till` looks forward and `since` looks back. A date on its own picks the **nearest** year, so a date
three days ago means three days ago, not next year.

A bare number after a moment means hours after a clock time and days after a date:
`3:45pm + 5` is 8:45 PM, and `august 5 + 5` is 10 August.

Month and year shifts follow the calendar: `31.1.26 + 1 month` lands on 28 February. `+ 1 day` keeps
the clock time across daylight saving; `+ 24 hours` adds exact hours.

Dates with dots are day first, like `19.2.27` for 19 February 2027, and `28. aug` works too. Dates
with slashes are month first. Two-digit years 00–68 mean the 2000s, and 69–99 the 1900s. Plain
fractions like `5/2 - 1/2` stay arithmetic.

### Workdays

`weekdays`, `business days`, `work days` and `working days` skip Saturday and Sunday:
`today + 5 business days`, `5 weekdays from now`. Public holidays are not counted.

As a unit on its own, a `workday` is eight hours: `55h in workdays`.

### Unix time

`now to unix` gives whole seconds and `now to unix ms` milliseconds. `unix 0 to date` and
`1000 unix ms` convert back. Timestamps like `2026-07-24T07:30:00+02:00 + 30min` work, with a `Z` or
an offset.

## Time zones

| You type                           | You get                            |
| ---------------------------------- | ---------------------------------- |
| `time in Tokyo`                    | The time there now                 |
| `what time is it in London`        | The same                           |
| `5pm ldn in sf`                    | 5 PM London time, in San Francisco |
| `9:30am in nyc`                    | Your 9:30 AM, in New York          |
| `5pm ldn in sf + 2h`               | The same, two hours later          |
| `time in sao paulo + 5`            | Five hours from now, there         |
| `diff paris`                       | How far Paris is from your time    |
| `time in 4 hours in san francisco` | San Francisco, four hours from now |

An answer on a different day says `(tomorrow)` or `(yesterday)`.

Cities come from the time zone database built into macOS, plus about a hundred common cities it does
not name, like Salzburg or Basel. Accents are optional, so `zurich` works. Common short names work
too: `pst`, `cet`, `jst`, `sf`, `nyc`, `ldn`, and airport codes like `lhr`, `nrt` and `sfo`.

It all works offline. Tinycast does not look cities up online.

## Percent, ratios and lists

| You type                | You get  |
| ----------------------- | -------- |
| `20% off 500`           | `400`    |
| `15% tip on 42`         | `6.3`    |
| `50 as % of 200`        | `25%`    |
| `50 is what % of 200`   | `25%`    |
| `30 is 20% of what`     | `150`    |
| `ratio of 1920 to 1080` | `16 : 9` |
| `average of 10, 20, 30` | `20`     |
| `round 47 to nearest 5` | `45`     |

The card labels what the number is, like **Tip**, **Discounted** or **Ratio**, instead of a bare
"Result".

## Functions and comparisons

Functions take comma-separated values: `hypot(3,4)`, `round(3.14159,2)`, `log(8,2)`, `gcd(12,18)`,
`lcm(4,6)`, `atan2(1,1)`, `pow(2,10)` and `root(-8,3)`. There are also inverse and hyperbolic trig
functions, `cbrt`, `exp`, `log2`, `sign` and `trunc`, and the constants `tau` and `phi`.

`min`, `max`, `sum`, `avg`, `mean` and `average` take lists, including measurements:
`sum(1km,500m)` is `1.5 km`. Inside a function, write `1000` rather than `1,000`, since commas
separate values there.

`==`, `!=`, `<`, `<=`, `>` and `>=` compare numbers or matching units: `1km == 1000m` is `true`.
Whole numbers support `&`, `|`, `xor`, `~`, `<<` and `>>`. `^` is always a power.

Base conversion works both ways: `0xff` reads Hexadecimal → Decimal, and `2m / 2m to hex` is `0x1`.

## Errors

Errors are kept for real mistakes: two units that do not fit together (`1kg + 1m`), or a unit against
a currency (`Cannot convert Currency to Weight.`).

Everything else stays quiet instead of flashing an error while you type. A half-typed calculation is
not a mistake. It is half typed.

## Calculator History

**Calculator History** is its own screen, opened by the command of that name. It stays out of the
<kbd>tab</kbd> loop; leave with <kbd>esc</kbd> or <kbd>delete</kbd> in an empty search.

| Action             | Shortcut                             |
| ------------------ | ------------------------------------ |
| Copy Answer        | <kbd>return</kbd>                    |
| Copy Expression    | <kbd>⌘</kbd><kbd>return</kbd>        |
| Delete Entry       | <kbd>⌃</kbd><kbd>X</kbd>             |
| Delete All Entries | <kbd>⌃</kbd><kbd>⇧</kbd><kbd>X</kbd> |

## Colors

Paste a color like `#FF5733`, `rgb(255, 87, 51)` or `hsl(11, 100%, 60%)` into the launcher and a
color card shows the swatch. <kbd>⌘</kbd><kbd>K</kbd> copies it as hex, `rgba()`, `hsl()` or
`oklch()`.
