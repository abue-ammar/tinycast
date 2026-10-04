---
title: Calculator
description: Math, units, live currency and crypto rates, dates and time zones, answered as you type.
---

Type a calculation into the launcher and the answer appears on a card above the results. There's no
separate calculator mode; Tinycast works out the answer as you type.

| Action                   | Shortcut                                  |
| ------------------------ | ----------------------------------------- |
| Copy Answer              | <kbd>return</kbd>                         |
| Put Answer in Search Bar | <kbd>⌘</kbd><kbd>return</kbd>             |
| Copy Calculation         | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>return</kbd> |

Copying the answer or putting it in the search bar also saves it to **Calculator History**. Only
numbers, units and money go in the search bar; a date, a time or a true/false answer does not.

A single word never shows a card. On their own, `tomorrow`, `july` and `pi` are treated as searches.

## Arithmetic

`4(2+3)` is 20. `2pi`, `2sqrt(9)` and `(2+3)(2+3)` all work, and `6/2(1+2)` gives the same answer as
`6/2*(1+2)`. A lone `x` between numbers also multiplies, so `3x3` and `$5 x 2` work. Two numbers
separated only by a space never multiply, so `5 3` stays a search.

Use `mod` for the remainder, because `%` already means percent. It has the same precedence as
multiply and divide, and keeps the sign of the first number: `-10 mod 3` is `-1`.

`10k` is `10,000`. Scientific notation works (`1e5`, `5e-3km`, `3e+2`), while `2e` and `2 e` mean
2 × Euler's _e_.

Spoken roots work with measurements: `square root of 25m2` is `5 m`.

**A trailing operator keeps the last answer on screen.** `10 +` shows `10`, and `10kg + 500g +`
shows `10,500 g`, so the card doesn't flicker while you type the next number.

## Units

**The last unit you type sets the unit of the answer.**

| You type            | You get                                      |
| ------------------- | -------------------------------------------- |
| `5feet + 1m`        | `2.524 m`                                    |
| `10kg + 500g`       | `10,500 g`                                   |
| `1kg + 500g + 2lb`  | pounds                                       |
| `10kg + 500g to lb` | pounds; a trailing `to` overrides everything |
| `10kg to lb + 3lb`  | converts, then adds                          |

**Units written side by side form one amount.** `5 feet 3 inches` is `5.25 ft` and `1hr 30min` is
`1.5 hr`, answered in the _first_ unit. These pairs are evaluated first, so `5w * 3h 30min` means
`5w * (3h 30min)`, and `90km / 1h 30min` gives `60 km/h`.

A number without a unit takes the unit next to it: `5kg+5` is `10 kg`, and `$10 + 5` is `15.00 USD`.

With `+` and `-`, a percentage is relative (`10kg + 20%` is `12 kg`). With `*` and `/`, it's a plain
fraction (`10kg * 3%` is `0.3 kg`, `10kg / 25%` is `40 kg`).

A unit on its own converts to a related unit: `1m` gives feet and inches, and `1hr` gives 60 min.

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

Results use base units unless you name a unit with `to` or `in`. Power multiplied by minutes or
hours gives Wh or kWh, and current multiplied by minutes or hours gives Ah or mAh. `m²` and `m2`
both mean square meters, while `(2m)^2` squares the whole amount. Use `pi * (2m)^2` for the area of
a circle.

`to timespan` splits a duration into parts: `145 mins to timespan` is `2 hr 25 min`. The largest
part is weeks, because months vary in length.

You can only add or subtract temperatures in the same scale. Other units combine freely:
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

Cubic units range from `mm³` to `m³`, plus `in³`, `ft³` and `yd³`. You can type `3` instead of `³`.
Liquid measures include mL, cL, dL, L, cups, tablespoons, teaspoons, and US gallons, quarts and
pints. Use `fl oz` for fluid ounces, because plain `oz` is weight. UK measures are `ukgal`, `ukqt`,
`ukpint` and `ukfloz`.

## Electrical

| You type                   | You get      |
| -------------------------- | ------------ |
| `5 watt * 3h 30min to kwh` | `0.0175 kWh` |
| `12V * 2A`                 | `24 W`       |
| `12V / 6ohm`               | `2 A`        |
| `12V / 2A`                 | `6 Ω`        |
| `500mA * 3h 30min`         | `1,750 mAh`  |
| `2000mAh / 500mA to hours` | `4 hr`       |

`C` means Celsius, so coulombs are shown as `As`. Mega and milli are case-sensitive: `MW` is
megawatts and `mW` is milliwatts.

## Pixels and density

| You type                               | You get           |
| -------------------------------------- | ----------------- |
| `3000px / 300ppi to inches`            | `10 in`           |
| `5in * 300ppi`                         | `1,500 px`        |
| `3000px / 10in to ppi`                 | `300 ppi`         |
| `sqrt((3840px)^2 + (2160px)^2) / 27in` | `163.1783089 ppi` |

Pixels have no fixed physical size, so include a density to convert them to inches or centimeters.
The last example calculates the pixel density of a 27-inch 4K display from its diagonal.

### REM and EM

| You type      | You get   |
| ------------- | --------- |
| `24px`        | `1.5 rem` |
| `2rem`        | `32 px`   |
| `16px to rem` | `1 rem`   |
| `1rem + 8px`  | `24 px`   |

`rem` and `em` use the browser's default root font size of 16px. `pt` means pints, not points. When
you copy a `px`, `rem` or `em` result, the space is removed (`24px`) so you can paste it into CSS.

## Data and transfer rates

`MB/s` is megabytes per second and `Mbps` is megabits per second, so `100Mbps to MB/s` is
`12.5 MB/s`. Binary units like `MiB/s` and bit amounts like `kbit` also work.

Other supported units include tonnes (`t`), stone (`st`), nautical miles (`nmi`), horsepower (`hp`),
BTU, `rpm` and pound-force (`lbf`).

## Currency and crypto

| You type                    | It means                   |
| --------------------------- | -------------------------- |
| `1 euro to dollars`         | Named currencies           |
| `€20 to GBP` / `20€ to GBP` | Symbols, on either side    |
| `eur to usd`                | An amount of 1             |
| `1 btc to eur`              | Crypto                     |
| `$10 + €5`                  | Mixed arithmetic           |
| `(20 sgd to usd) * 30`      | Convert, then multiply     |
| `100 USD / 4hr`             | `25 USD/hr`                |
| `25 USD/hr to EUR/min`      | A rate in another currency |

Tinycast supports 159 currencies and a selected list of cryptocurrencies.

**An amount on its own is converted to your Mac's currency.** On a Mac set to Bangladesh, `1 usd`
shows `122.84 BDT`. If you type an amount in your own currency, it's converted to US dollars, or to
euros if your currency is the dollar. Your currency comes from your Mac's region setting.
**Tinycast never asks for your location.**

### Words with two meanings

Some currency words are shared by several countries: `dollars` could mean 22 currencies, `francs`
10, `pounds` 9, `pesos` 8 and `rupees` 6. Tinycast maps each of these to one currency. If a word is
still ambiguous, Tinycast shows **no card**. For example, `krona` could be Swedish or Icelandic, so
Tinycast doesn't guess.

Slang isn't supported: **`quid` and `bucks` show no card.** `rmb` and `renminbi` work, because the
ISO 4217 standard names the currency "Yuan Renminbi".

Units take priority over currencies, so `10 pounds to kg` is a weight, `10 pounds to euros` is money,
and `1 cup to ml` is a volume even though `CUP` is also the Cuban peso. Crypto tickers take priority
over words: `1 sol` is Solana, while `soles` means the Peruvian sol.

### Rates

Rates are saved on your Mac and refreshed every 24 hours, counted from when they were saved.
Restarting Tinycast doesn't refresh them early, so if the saved rates are recent, opening Tinycast
makes **no** network requests.

Crypto prices are best effort. If they fail to load, currencies still work, and Tinycast tries
loading crypto prices again in 30 minutes.

When you're offline, the last saved rates keep working. If no rates have been saved yet, the card
says so instead of guessing. A currency without a rate shows `No exchange rate for <CODE>.`

Money is rounded to two decimal places, or to four significant digits for amounts under a cent, and
is always written out in full: `1 IDR to USD` is `0.00005539 USD`, never `5.539e-05`.

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

**When the answer is a date, Tinycast also shows the day of the week.**

`till` looks forward and `since` looks back. A date without a year uses the **nearest** year, so a
date three days in the past means three days ago, not next year.

A number without a unit after a moment means hours after a time and days after a date: `3:45pm + 5`
is 8:45 PM, and `august 5 + 5` is 10 August.

Adding months and years follows the calendar: `31.1.26 + 1 month` gives 28 February. `+ 1 day` keeps
the same clock time across daylight saving changes, while `+ 24 hours` adds exactly 24 hours.

Dates with dots are day first, like `19.2.27` for 19 February 2027, and `28. aug` also works. Dates
with slashes are month first. Two-digit years from 00 to 68 mean the 2000s, and 69 to 99 mean the
1900s. Simple fractions like `5/2 - 1/2` are still treated as arithmetic.

### Workdays

`weekdays`, `business days`, `work days` and `working days` skip Saturdays and Sundays, as in
`today + 5 business days` or `5 weekdays from now`. Public holidays aren't skipped.

As a unit on its own, a `workday` is eight hours: `55h in workdays`.

### Unix time

`now to unix` gives whole seconds and `now to unix ms` gives milliseconds. `unix 0 to date` and
`1000 unix ms` convert back to dates. Timestamps like `2026-07-24T07:30:00+02:00 + 30min` work with
either a `Z` or an offset.

## Time zones

| You type                           | You get                            |
| ---------------------------------- | ---------------------------------- |
| `time in Tokyo`                    | The current time there             |
| `what time is it in London`        | The same                           |
| `5pm ldn in sf`                    | 5 PM London time, in San Francisco |
| `9:30am in nyc`                    | Your 9:30 AM, in New York          |
| `5pm ldn in sf + 2h`               | The same, two hours later          |
| `time in sao paulo + 5`            | The time there in five hours       |
| `diff paris`                       | The time difference to Paris       |
| `time in 4 hours in san francisco` | San Francisco, four hours from now |

If the answer falls on a different day, it says `(tomorrow)` or `(yesterday)`.

Cities come from the time zone database built into macOS, plus about a hundred common cities that it
doesn't include, like Salzburg or Basel. Accents are optional, so `zurich` works. Common
abbreviations also work, like `pst`, `cet`, `jst`, `sf`, `nyc` and `ldn`, as do airport codes like
`lhr`, `nrt` and `sfo`.

Time zone answers work offline. Tinycast doesn't look up cities online.

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

The card labels the answer, like **Tip**, **Discounted** or **Ratio**, instead of a generic
"Result".

## Functions and comparisons

Functions take comma-separated values: `hypot(3,4)`, `round(3.14159,2)`, `log(8,2)`, `gcd(12,18)`,
`lcm(4,6)`, `atan2(1,1)`, `pow(2,10)` and `root(-8,3)`. There are also inverse and hyperbolic trig
functions, `cbrt`, `exp`, `log2`, `sign` and `trunc`, and the constants `tau` and `phi`.

`min`, `max`, `sum`, `avg`, `mean` and `average` take lists, including measurements:
`sum(1km,500m)` is `1.5 km`. Inside a function, write `1000` instead of `1,000`, because commas
separate the values.

`==`, `!=`, `<`, `<=`, `>` and `>=` compare numbers or compatible units: `1km == 1000m` is `true`.
Whole numbers support `&`, `|`, `xor`, `~`, `<<` and `>>`. `^` always means a power.

Base conversion works both ways: `0xff` shows Hexadecimal → Decimal, and `2m / 2m to hex` is `0x1`.

## Errors

The calculator only shows an error for real mistakes, like combining two units that don't fit
together (`1kg + 1m`) or a unit and a currency (`Cannot convert Currency to Weight.`).

For anything else, it shows nothing rather than flashing an error while you're still typing.

## Calculator History

**Calculator History** is a separate screen that you open with the command of the same name. It
isn't part of the <kbd>tab</kbd> cycle. To leave it, press <kbd>esc</kbd>, or <kbd>delete</kbd> in
an empty search.

| Action                                         | Shortcut                             |
| ---------------------------------------------- | ------------------------------------ |
| Copy Answer                                    | <kbd>return</kbd>                    |
| Copy Expression, on a past entry               | <kbd>⌘</kbd><kbd>return</kbd>        |
| Put Answer in Search Bar, on a new calculation | <kbd>⌘</kbd><kbd>return</kbd>        |
| Delete Entry                                   | <kbd>⌃</kbd><kbd>X</kbd>             |
| Delete All Entries                             | <kbd>⌃</kbd><kbd>⇧</kbd><kbd>X</kbd> |

## Colors

Paste a color like `#FF5733`, `rgb(255, 87, 51)` or `hsl(11, 100%, 60%)` into the launcher and a
card shows the color. <kbd>⌘</kbd><kbd>K</kbd> lets you copy it as hex, `rgba()`, `hsl()` or
`oklch()`.
