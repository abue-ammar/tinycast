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

You can ask in words. `what is 20% of 50`, `calculate 2 + 3` and `20% of 50?` all show `10` or
`5`, and a leading `what is` that doesn't fit falls back to the whole question, so
`what is the time in tokyo` still works.

Most single words never show a card. On their own, `monday`, `july` and `pi` are treated as
searches. The exceptions name one moment: `today`, `tomorrow` and `yesterday` show the date, `now`
shows the date and time, and `time` shows the time on your Mac.

## Arithmetic

`4(2+3)` is 20. `2pi`, `2sqrt(9)` and `(2+3)(2+3)` all work, and `6/2(1+2)` gives the same answer as
`6/2*(1+2)`. A lone `x` between numbers also multiplies, so `3x3` and `$5 x 2` work. Two numbers
separated only by a space never multiply, so `5 3` stays a search.

Use `mod` for the remainder, because `%` already means percent. It has the same precedence as
multiply and divide, and keeps the sign of the first number: `-10 mod 3` is `-1`.

`10k` is `10,000`. Scientific notation works (`1e5`, `5e-3km`, `3e+2`), while `2e` and `2 e` mean
2 × Euler's _e_. Right after a currency, `M`, `bn` and `T` also work: `$2M / 4` is `500,000.00 USD`.

Spoken roots work with measurements: `square root of 25m2` is `5 m`. `root 4 of 81` is `3`, and
`log 81 base 3` is `4`.

You can also write the operators as words: `10 plus 5`, `10 minus 3`, `6 times 7`,
`10 divided by 2`, `10 multiplied by 3` and `2 to the power of 10`. `3 raised to 4`, `2 exponent 10`
and `3 to the 4` are powers too. `4 squared` is `16` and `3 cubed` is `27`. `per` means divide, so
`60 miles per hour` is `60 mi/hr`. `percent`, `per cent` and `percentage` mean `%`, so
`20 percent of 50` is `10`.

`thousand`, `million`, `billion`, `trillion` and `quadrillion` scale the number before them:
`2 trillion` is `2,000,000,000,000`.

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

**A fraction right before a unit is one amount.** `5/16" in mm` is `7.9375 mm`, `1 1/2 cups to ml`
works, and `5'10" in cm` is `177.8 cm`. With spaces around it, `/` still divides, so
`1 / 20ms to hz` is `50 Hz`.

With `+` and `-`, a percentage is relative (`10kg + 20%` is `12 kg`). With `*` and `/`, it's a plain
fraction (`10kg * 3%` is `0.3 kg`, `10kg / 25%` is `40 kg`).

A unit on its own converts to a related unit: `1m` gives feet and inches, and `1hr` gives 60 min.

**You can ask for a conversion in words:**

| You type                        | You get          |
| ------------------------------- | ---------------- |
| `convert 5 km into miles`       | `3.106855961 mi` |
| `5 km is what in miles`         | `3.106855961 mi` |
| `5 km is how many miles`        | `3.106855961 mi` |
| `how many feet in a mile`       | `5,280 ft`       |
| `how many seconds are in a day` | `86,400 s`       |
| `seconds in 3 days`             | `259,200 s`      |
| `cm in 5 inches`                | `12.7 cm`        |

After `in`, the amount needs a number or `a`/`an`. Without one, `m in ft` still means one meter in
feet.

Months and years convert as averages: a year is 365.2425 days and a month is a twelfth of that, so
`3 months to days` is `91.310625 day` and `12 months to years` is `1 yr`. Adding a month to a date
still follows the calendar (see [Dates and times](#dates-and-times)).

**A conversion can sit in the middle of a calculation.** `1000 usd in eur / 12` converts first,
then divides, and `round(1000 usd in eur)` works too.

A unit right after `/` means one of that unit, so `100 / s to hz` is `100 Hz`.

Measurements combine into area, volume, speed and more:

| You type                     | You get       |
| ---------------------------- | ------------- |
| `5m * 4m`                    | `20 m²`       |
| `2m * 3m * 4m to l`          | `24,000 L`    |
| `sqrt(25m2)`                 | `5 m`         |
| `cube root of -8m3`          | `-2 m`        |
| `100km / 2h to km/h`         | `50 km/h`     |
| `90km/h * 20min to km`       | `30 km`       |
| `60 mph * 2.5 hours`         | `150 mi`      |
| `100km / 40km/h to duration` | `2 hr 30 min` |
| `1GB / 100mbps to s`         | `80 s`        |
| `1500w * 2h to kwh`          | `3 kWh`       |
| `1 / 20ms to hz`             | `50 Hz`       |

Results use base units unless you name a unit with `to`, `in` or `as`. A rate multiplied by time
keeps the rate's own unit, so `10 l/min * 30 s` is `5 L`. Power multiplied by minutes or hours gives
Wh or kWh, and current multiplied by minutes or hours gives Ah or mAh. `m²` and `m2`
both mean square meters, while `(2m)^2` squares the whole amount. Use `pi * (2m)^2` for the area of
a circle.

`to timespan` splits a duration into parts: `145 mins to timespan` is `2 hr 25 min`. The largest
part is weeks, because months vary in length.

**Name two units of the same kind to split an answer between them.** The larger unit is whole, and
the rest goes into the smaller one. Join them with `and`, `&` or just a space:

| You type                          | You get               |
| --------------------------------- | --------------------- |
| `1.75 m to feet and inches`       | `5 ft 8.897637795 in` |
| `2.5 kg to lb oz`                 | `5 lb 8.184904874 oz` |
| `2.75 hours in hours and minutes` | `2 hr 45 min`         |
| `100 months to years and months`  | `8 yr 4 mo`           |
| `100 days to weeks and days`      | `14 week 2 day`       |

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
`ukpint` and `ukfloz`, or written out as `imperial gallons`, `imperial pints` and
`imperial tablespoons`.

## Electrical

| You type                   | You get      |
| -------------------------- | ------------ |
| `5 watt * 3h 30min to kwh` | `0.0175 kWh` |
| `12V * 2A`                 | `24 W`       |
| `12V / 6ohm`               | `2 A`        |
| `12V / 2A`                 | `6 Ω`        |
| `500mA * 3h 30min`         | `1,750 mAh`  |
| `2000mAh / 500mA to hours` | `4 hr`       |
| `12V * 2s`                 | `24 Wb`      |
| `1 microfarad * 1 kiloohm` | `0.001 s`    |

`C` means Celsius, so coulombs are shown as `As`. Mega and milli are case-sensitive: `MW` is
megawatts and `mW` is milliwatts.

Capacitance (`farad`, `µF`, `nF`, `pF`), inductance (`henry`, `mH`), conductance (`siemens`),
magnetic flux (`weber`, `Wb`), magnetic flux density (`tesla`, `mT`, `gauss`), torque (`Nm`,
`lb ft`) and amount of substance (`mol`, `mmol`) all work, and they combine with the units above.
Write these names out or with a prefix: a bare `F` is still Fahrenheit, `H` hours, `S` seconds and
`T` tonnes. `10 newton meters to pound feet` is `7.375621493 lb·ft`.

## Pixels and density

| You type                               | You get           |
| -------------------------------------- | ----------------- |
| `3000px / 300ppi to inches`            | `10 in`           |
| `5in * 300ppi`                         | `1,500 px`        |
| `3000px / 10in to ppi`                 | `300 ppi`         |
| `sqrt((3840px)^2 + (2160px)^2) / 27in` | `163.1783089 ppi` |
| `3000 px to inches at 300 ppi`         | `10 in`           |
| `10 cm to px at 300 ppi`               | `1,181.102362 px` |
| `ppi of 27 inch display at 3840x2160`  | `163.1783089 ppi` |

Pixels have no fixed physical size, so include a density to convert them to inches or centimeters,
either with `/` and `*` or with `at`. The pixel density of a display comes from its diagonal, so
`ppi of 27 inch display at 3840x2160` and the `sqrt` example give the same answer.

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

`MB/s` and `MBps` are megabytes per second and `Mbps` is megabits per second, so `100Mbps to MB/s`
is `12.5 MB/s`. Binary units like `MiB/s` and bit amounts like `kbit` also work.

Other supported units include tonnes (`t`), stone (`st`), carats (`ct`), troy ounces (`ozt`),
nautical miles (`nmi`), light years (`ly`), parsecs (`pc`), astronomical units (`au`), fathoms,
furlongs, barrels (`bbl`), bushels (`bu`), acre feet, metric cups, microliters and kiloliters, cubic
kilometers and miles, GWh and TWh, horsepower (`hp`), BTU, `rpm`, `rps` and `rad/s`, pound-force
(`lbf`), poundals (`pdl`), `ksi`, `ft/s2`, and data sizes up to yottabytes. Spelled-out names work
too, like `nautical miles`, `sq ft`, `square feet` and `cubic feet`. `°` means degrees, so
`cos(60°)` is `0.5`.

## Fuel and pace

Fuel economy uses `mpg` and `km/L`, and fuel consumption uses `L/100km`. `15 km/l to mpg` is
`35.2821875 mpg`, and `100 mi / 4 gal to mpg` is `25 mpg`. Economy and consumption convert directly
into each other, as do speed and pace:

| You type                    | You get               |
| --------------------------- | --------------------- |
| `30 mpg to l/100km`         | `7.840486111 L/100km` |
| `6.5 l/100km to mpg`        | `36.18685897 mpg`     |
| `8 l/100km to km/l`         | `12.5 km/L`           |
| `100 mi / 4 gal to l/100km` | `9.408583333 L/100km` |
| `10 km/h to min/km`         | `6 min/km`            |
| `6 min/km to km/h`          | `10 km/h`             |

## Currency and crypto

| You type                            | It means                   |
| ----------------------------------- | -------------------------- |
| `1 euro to dollars`                 | Named currencies           |
| `€20 to GBP` / `20€ to GBP`         | Symbols, on either side    |
| `eur to usd`                        | An amount of 1             |
| `exchange rate for usd to eur`      | The same, in words         |
| `1 btc to eur`                      | Crypto                     |
| `$10 + €5`                          | Mixed arithmetic           |
| `(20 sgd to usd) * 30`              | Convert, then multiply     |
| `100 USD / 4hr`                     | `25 USD/hr`                |
| `25 USD/hr to EUR/min`              | A rate in another currency |
| `5 usd per gallon to eur per liter` | A spoken rate, converted   |

Tinycast supports 159 currencies and a selected list of cryptocurrencies.

**An amount on its own is converted to your Mac's currency.** On a Mac set to Bangladesh, `1 usd`
shows `122.84 BDT`. If you type an amount in your own currency, it's converted to US dollars, or to
euros if your currency is the dollar. Your currency comes from your Mac's region setting.
**Tinycast never asks for your location.**

A rate on its own converts the same way and keeps its unit: on a Mac set to the UK,
`5 usd per gallon` shows `3.95 GBP/gal`. Add a target to pick the currency, as in
`5 USD/gal to EUR/gal`.

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

A money answer shows when the rates were last updated. Click the refresh button next to it to load
new rates now.

Crypto prices are best effort. If they fail to load, currencies still work, and Tinycast tries
loading crypto prices again in 30 minutes.

When you're offline, the last saved rates keep working. If no rates have been saved yet, the card
says so instead of guessing. A currency without a rate shows `No exchange rate for <CODE>.`

Money is rounded to two decimal places, or to four significant digits for amounts under a cent, and
is always written out in full: `1 IDR to USD` is `0.00005539 USD`, never `5.539e-05`.

## Dates and times

| What you want                | Example                                              |
| ---------------------------- | ---------------------------------------------------- |
| Time until a moment          | `hrs till 9am`, `days till 9april`                   |
| Time since a moment          | `days since 9jul`, `hrs since noon`                  |
| A moment plus or minus       | `today + 3 weeks`, `now + 90 min`                    |
| A chain of shifts            | `17.2.26 + 100 weekdays - 4 + 2`                     |
| Months and years             | `31.1.26 + 1 month`, `29.2.24 + 1 year`              |
| The gap between two          | `jul 4 - today`, `9:30 - 7:00 to minutes`            |
| The span between two         | `may 1 to may 31`, `days between june 1 and june 29` |
| The span between two times   | `from 9:15 to 17:45`, `10pm to 2am`                  |
| From or before a moment      | `3 days from next monday at 7:30`, `2 weeks ago`     |
| After or before a date       | `2 weeks after august 3`, `3 days before christmas`  |
| A weekday in a later week    | `monday in 3 weeks`, `friday in 2 weeks`             |
| A named moment               | `tomorrow at 9am`, `next monday`, `aug 25`           |
| A day from now               | `in 3 days`, `next week`, `last month`               |
| The start or end of a period | `end of month`, `start of next year`                 |
| A day with an ordinal        | `days until 29th of october`, `october 28th`         |
| A short day and month        | `days until 29.10`, `days since 20.7.`               |
| A holiday                    | `days until christmas`, `halloween + 3 days`         |
| A fact about a date          | `week number`, `day of year`, `age 3 may 1990`       |
| The day of the week          | `weekday on 1 january 2030`                          |
| Days in a month              | `days in february 2028`                              |
| How much of a period is left | `days left in 2026`, `hours left in today`           |
| How long a period is         | `days in 2028`, `weeks in 2026`, `workdays in march` |
| Whole units between two      | `whole weeks between jan 1 and mar 1`                |
| The middle of a span         | `halfway between jan 1 and mar 1`                    |
| Week or day of the month     | `week of month`, `day of the month on dec 25`        |
| A holiday in a given year    | `easter 2027`, `chinese new year 2027`               |

**When the answer is a date, Tinycast also shows the day of the week.**

`till` looks forward and `since` looks back. A date without a year uses the **nearest** year, so a
date three days in the past means three days ago, not next year.

A number without a unit after a moment means hours after a time and days after a date: `3:45pm + 5`
is 8:45 PM, and `august 5 + 5` is 10 August.

In a span, `through` counts the last day too: `may 1 through may 31` is 31 days. Two times without a
date run forward, so `10pm to 2am` is 4 hours.

Adding months and years follows the calendar: `31.1.26 + 1 month` gives 28 February. `+ 1 day` keeps
the same clock time across daylight saving changes, while `+ 24 hours` adds exactly 24 hours.

Dates with dots are day first, like `19.2.27` for 19 February 2027, and `28. aug` also works. Dates
with slashes are month first. Two-digit years from 00 to 68 mean the 2000s, and 69 to 99 mean the
1900s. Simple fractions like `5/2 - 1/2` are still treated as arithmetic.

`previous friday` is `last friday`, `this friday` is the Friday of this week (today, on a Friday),
`midday` is noon, and `5 p.m.` is `5 pm`.

In `days left in 2026`, what's left starts tomorrow, because part of today isn't a whole day.
`hours left in today` counts from now. A period can be `the year`, `this month`, `today`, a year
like `2028`, or a month like `march`.

Week numbers follow your Mac's calendar settings, so they can differ by one between regions.

### Holidays

| Holiday                 | Example                                       | You get                     |
| ----------------------- | --------------------------------------------- | --------------------------- |
| Easter and its days     | `easter 2027`, `good friday 2027`             | `28 March, 2027`            |
| Orthodox Easter         | `orthodox easter 2027`                        | `2 May, 2027`               |
| Chinese New Year        | `chinese new year 2027`                       | `6 February, 2027`          |
| Ramadan, start and end  | `ramadan 2027`, `end of ramadan 2027`         | `8 February, 2027 (±1 day)` |
| Eid al-Fitr             | `eid al-fitr 2027`, `eid ul fitr 2027`        | `9 March, 2027 (±1 day)`    |
| Eid al-Adha             | `eid al-adha 2027`, `eid-ul-azha 2027`        | `16 May, 2027 (±1 day)`     |
| Hanukkah, start and end | `hanukkah 2026`, `end of hanukkah 2026`       | `4 December 2026`           |
| Fixed days              | `days until christmas`, `boxing day + 3 days` |                             |

Holidays work like any other date: `days until easter`, `days since ramadan`,
`ramadan 2027 through end of ramadan 2027` or `weekday on chinese new year 2027`. On its own, a
holiday's name is treated as a search, so add a year or a calculation.

The fixed days are Christmas (`xmas`), Christmas Eve, Boxing Day, New Year's Day, New Year's Eve
(`nye`), Halloween, Valentine's Day and Orthodox Christmas. Easter follows the Western church
calendar, and Orthodox Easter the Eastern one. Hanukkah starts on the evening the first candle is
lit. Holidays that differ by country, like Thanksgiving, aren't included.

**Ramadan and the two Eids depend on the moon.** Tinycast uses the Umm al-Qura calendar. Where the
day is decided by a local moon sighting, it can come a day earlier or later, so the card adds
`(±1 day)` to any answer that depends on one, like `days until eid al-adha`. Copying the answer gives
it without the note. `eid` on its own could mean either Eid, so write `eid al-fitr` or
`eid al-adha`.

### Workdays

`weekdays`, `business days`, `work days` and `working days` skip Saturdays and Sundays, as in
`today + 5 business days` or `5 weekdays from now`. Public holidays aren't skipped.

To count workdays between two dates, use `workdays between july 27 and august 7` or
`august 3 to august 14 in workdays`.

As a unit on its own, a `workday` is eight hours: `55h in workdays`.

### Unix time

`now to unix`, `current timestamp` and `new timestamp` give whole seconds, and `now to unix ms`
gives milliseconds. `now to iso` gives an ISO 8601 date like `2026-07-24T00:18:00+00:00`.
`unix 0 to date`, `1000 unix ms` and `1800000000 to date` convert back to dates. A 13-digit number
is read as milliseconds. Timestamps like `2026-07-24T07:30:00+02:00 + 30min` work with
either a `Z` or an offset.

## Time zones

| You type                                   | You get                            |
| ------------------------------------------ | ---------------------------------- |
| `time in Tokyo`                            | The current time there             |
| `what time is it in London`                | The same                           |
| `5pm ldn in sf`                            | 5 PM London time, in San Francisco |
| `9:30am in nyc`                            | Your 9:30 AM, in New York          |
| `5pm ldn in sf + 2h`                       | The same, two hours later          |
| `time in sao paulo + 5`                    | The time there in five hours       |
| `diff paris`                               | The time difference to Paris       |
| `diff london & tokyo`                      | The difference between two places  |
| `time difference between london and tokyo` | The same                           |
| `local time in tokyo`                      | The current time there             |
| `date in tokyo`                            | Today's date there                 |
| `time in tokyo when it's 5pm in london`    | 5 PM London time, in Tokyo         |
| `time in 4 hours in san francisco`         | San Francisco, four hours from now |
| `oct 28 1pm et in cet`                     | A time on a given day, in Paris    |
| `tomorrow 3pm pst`                         | 3 PM tomorrow in Los Angeles, here |
| `10am utc+5:30 in london`                  | A UTC offset, in London            |
| `9am-5pm et in cet`                        | A span of time, in Paris           |
| `1pm et in london, tokyo, sydney`          | Several places on one card         |

If the answer falls on a different day, it says `(tomorrow)` or `(yesterday)`. A time with a date
uses daylight saving for that date, not for today. In a span, an end before the start means the
next day, so `10pm-2am` runs overnight.

Cities come from the time zone database built into macOS, plus about a hundred common cities that it
doesn't include, like Salzburg or Basel. Accents are optional, so `zurich` works. Common
abbreviations also work, like `pst`, `cet`, `jst`, `sf`, `nyc` and `ldn`, as do airport codes like
`lhr`, `nrt` and `sfo`.

Time zone answers work offline. Tinycast doesn't look up cities online.

## Percent, ratios and lists

| You type                    | You get                         |
| --------------------------- | ------------------------------- |
| `20% off 500`               | `400`                           |
| `25% off $60`               | `45.00 USD`                     |
| `take 20% off 100`          | `80`                            |
| `20% discount off $100`     | `80.00 USD`                     |
| `15% on 80`                 | `92`                            |
| `15% tip on 42`             | `6.3`                           |
| `50 as % of 200`            | `25%`                           |
| `30 as a % of 120`          | `25%`                           |
| `50 is what % of 200`       | `25%`                           |
| `what % is 25 of 100`       | `25%`                           |
| `750 m as % of 3 km`        | `25%`                           |
| `4 out of 10`               | `40%`                           |
| `10 is what % with 20`      | `33.33333333%`                  |
| `30 is 20% of what`         | `150`                           |
| `20% of what is 30`         | `150`                           |
| `90 is 10% off what`        | `100`                           |
| `45 is what % off 50`       | `10%`                           |
| `80 to 100 is what %`       | `25%`                           |
| `% change from 10 to 20`    | `100%`                          |
| `% decrease from 20 to 10`  | `-50%`                          |
| `15 as % after adding 3`    | `25%`                           |
| `if 30 is 20%, what is 50%` | `75`                            |
| `if 30 is 20% what is 60`   | `40%`                           |
| `10% tax on 100`            | `110`                           |
| `20% vat in 120`            | `20` (the tax inside the price) |
| `$100 + 10% tax`            | `110.00 USD`                    |
| `0.125 as %`                | `12.5%`                         |
| `half of $90`               | `45.00 USD`                     |
| `ratio of 1920 to 1080`     | `16 : 9`                        |

A word between the percentage and `of`, `on` or `off` only names it, so `20% discount off $100` is
`20% off $100`. The exception is `tip`: `15% tip on 42` is the tip on its own. `tax`, `sales tax`,
`vat` and `gst` all work the same way.

### Lists and statistics

| You type                                       | You get       |
| ---------------------------------------------- | ------------- |
| `average of 10, 20, 30`                        | `20`          |
| `median of 3, 1, 2`                            | `2`           |
| `count of 4, 8, 15, 16, 23, 42`                | `6`           |
| `standard deviation of 2, 4, 4, 4, 5, 5, 7, 9` | `2.138089935` |
| `sum of 1 km and 500 m`                        | `1.5 km`      |
| `larger of 3 and 7`                            | `7`           |
| `midpoint between 10 and 30`                   | `20`          |
| `gcd of 12 and 18`                             | `6`           |
| `gcf of 20 and 30`                             | `10`          |
| `lowest common multiple of 4 and 6`            | `12`          |

Separate items with commas or `and`. Units are kept, as in `sum of 1 km and 500 m`. The standard
deviation is the sample deviation, the same as `STDEV` in a spreadsheet.

The amount keeps its currency or unit. The card labels the answer, like **Tip**, **Discounted**,
**Percent Change**, **Ratio** or **Median**, instead of a generic "Result".

## Math in words

| You type                              | You get |
| ------------------------------------- | ------- |
| `is 97 prime`                         | `true`  |
| `is 91 a prime number`                | `false` |
| `remainder of 20 divided by 3`        | `2`     |
| `clamp 20 between 5 and 15`           | `15`    |
| `6 is to 600 as 8 is to what`         | `800`   |
| `2 km is to 4 km as what is to 10 kg` | `5 kg`  |
| `5 choose 3`                          | `10`    |
| `5 permutation 3`                     | `60`    |
| `logarithm 81 base 3`                 | `4`     |
| `1000 is 10 to the power of what`     | `3`     |
| `5 root of 32`                        | `2`     |
| `5 as multiplier of 1`                | `5x`    |
| `10 to 20 as multiplier`              | `2x`    |

Prime checks work for every whole number up to 9,007,199,254,740,992 and answer instantly.

## Rounding and fractions

| You type                            | You get        |
| ----------------------------------- | -------------- |
| `2/3 to 3 dp`                       | `0.667`        |
| `pi to 2 decimal places`            | `3.14`         |
| `2.5 rounded`                       | `3`            |
| `2.1 rounded up`                    | `3`            |
| `round 47 to nearest 5`             | `45`           |
| `44 rounded up to nearest 10`       | `50`           |
| `$1,240 rounded to nearest hundred` | `1,200.00 USD` |
| `0.625 as fraction`                 | `5/8`          |
| `round 56.2 up`                     | `57`           |
| `round 51 to next 10`               | `60`           |
| `round 59 down to last 10`          | `50`           |
| `round 56 up to 10`                 | `60`           |
| `3.3 to nearest quarter`            | `3.25`         |
| `round 56.789 to 1 digit`           | `56.8`         |
| `0.75 to fraction`                  | `3/4`          |

A number that has no simple fraction, like `pi as fraction`, shows no card. `round 56 to 10` shows
no card either, because it could mean ten decimal places; add `up`, `down` or `nearest`.

### Other formats

| You type                          | You get          |
| --------------------------------- | ---------------- |
| `1234567 to sci`                  | `1.234567e6`     |
| `0.000123 to scientific notation` | `1.23e-4`        |
| `51.4772° to dms`                 | `51° 28′ 37.92″` |
| `5400 seconds to hms`             | `1h 30m 0s`      |
| `75.5 seconds to laptime`         | `00:01:15.5`     |
| `255 to base 7`                   | `513`            |
| `2 to multiplier`                 | `2x`             |

`to base` takes any base from 2 to 36.

## Interest and loans

| You type                                                    | You get            |
| ----------------------------------------------------------- | ------------------ |
| `$2,000 after 5 years at 4%`                                | `2,433.31 USD`     |
| `$2,000 at 4% for 5 years compounding quarterly`            | `2,440.38 USD`     |
| `interest on $2,000 after 5 years at 4%`                    | `433.31 USD`       |
| `monthly payment on $20,000 over 5 years at 6%`             | `386.66 USD`       |
| `total payment on $20,000 over 5 years at 6%`               | `23,199.36 USD`    |
| `total interest on $10,000 for 5 years at 6%`               | `1,599.68 USD`     |
| `monthly interest on $10,000 for 5 years at 6%`             | `26.66 USD`        |
| `present value of $1000 after 5 years at 5%`                | `783.53 USD`       |
| `500 invested 1000 returned`                                | `100%`             |
| `annual return on 500 invested 1000 returned after 5 years` | `14.8698355%`      |
| `investment required for $50000/year at 4%`                 | `1,250,000.00 USD` |

Interest is added once a year unless you add `compounding monthly`, `quarterly` or `daily`. Loan
payments are monthly; `annual payment` gives twelve of them. `annual return` is the yearly growth
rate (CAGR), and `investment required` is the amount whose yearly interest pays that much.

## Growth and decay

| You type                                       | You get          |
| ---------------------------------------------- | ---------------- |
| `20 after 5 years at 5% every year`            | `25.52563125`    |
| `20 after 5 years at 5% decay every year`      | `15.47561875`    |
| `time from 20 to 30 at 5% every year`          | `8.310386223 yr` |
| `time from 20 to 30 at 2 every day`            | `5 day`          |
| `growth every year from 20 to 30 over 5 years` | `8.44717712%`    |

## Rates, downloads and playback speed

| You type                     | You get             |
| ---------------------------- | ------------------- |
| `$50/hr for 3 hours`         | `150.00 USD`        |
| `60 km/h for 30 min`         | `30 km`             |
| `$100,000/year for 3 months` | `25,000.00 USD`     |
| `$50/hr is what per day`     | `1,200.00 USD/day`  |
| `download 20 GB at 10 MB/s`  | `33 min 20 s`       |
| `transfer 1 TB at 100 Mbps`  | `22 hr 13 min 20 s` |
| `1 hour at 2x`               | `0.5 hr`            |
| `90 min at 1.5× speed`       | `60 min`            |
| `time saved 1 hour at 1.5x`  | `0.3333333333 hr`   |

`download`, `upload`, `transfer` and `send` all work.

## Cooking

| You type                  | You get             |
| ------------------------- | ------------------- |
| `1 cup of flour in grams` | `125 g`             |
| `200 g butter in cups`    | `0.8810572687 cup`  |
| `2 tbsp honey to g`       | `42.375 g`          |
| `density of honey`        | `1.432869212 g/cm³` |

About 40 common ingredients convert between weight and volume, including flour, sugars, butter,
oils, honey, milk, rice, oats, salt and cocoa. The weights come from USDA's grams-per-cup figures.
An ingredient that isn't on the list shows no card.

## Music

`440 hz to pitch` is `A4`, the nearest note with A4 at 440 Hz, and `c4 to hz` is `261.6255653 Hz`.
Write notes as a letter, an optional `b` for flat, and an octave, like `bb3`.

## Splitting a bill

| You type                 | You get       |
| ------------------------ | ------------- |
| `$120 split 4`           | `30.00 USD`   |
| `split 120 between 4`    | `30`          |
| `85 + 20% split 3`       | `34`          |
| `20% tip on 85 split 3`  | `5.666666667` |
| `eur 99 among 3 friends` | `33.00 EUR`   |
| `120 / 4 people`         | `30`          |

The card labels the answer **Per Person**. The amount keeps the currency or unit you typed, so
`$120 split 4` is `30.00 USD` on any Mac.

## Functions and comparisons

Functions take comma-separated values: `hypot(3,4)`, `round(3.14159,2)`, `log(8,2)`, `gcd(12,18)`,
`lcm(4,6)`, `atan2(1,1)`, `pow(2,10)` and `root(-8,3)`. There are also inverse and hyperbolic trig
functions, `cbrt`, `exp`, `log2`, `sign` and `trunc`, and the constants `tau` and `phi`.

`min`, `max`, `sum`, `avg`, `mean`, `average`, `median` and `stddev` take lists, including
measurements, and `count` counts them:
`sum(1km,500m)` is `1.5 km`. Inside a function, write `1000` instead of `1,000`, because commas
separate the values. If your number format uses a decimal comma, separate values with `;` instead,
as in `max(2,5; 3)`.

`==`, `!=`, `<`, `<=`, `>` and `>=` compare numbers or compatible units: `1km == 1000m` is `true`.
Whole numbers support `&`, `|`, `xor`, `~`, `<<` and `>>`. `^` always means a power.

Base conversion works both ways: `0xff` shows Hexadecimal → Decimal, `256 as hex` is `0x100`, and
`2m / 2m to hex` is `0x1`.

## Errors

The calculator only shows an error for real mistakes, like combining two units that don't fit
together (`1kg + 1m`) or a unit and a currency (`Cannot convert Currency to Weight.`).

For anything else, it shows nothing rather than flashing an error while you're still typing.

## Number format

**Settings → General → Calculator → Number format** sets how you write numbers and how answers are
shown. **System** (the default) follows your Mac's Language & Region settings, so with a decimal
comma, `2,3 + 1,5` is `3,8`. **English** always uses a decimal point and comma grouping.

With a decimal comma, separate function values and list items with `;`. If a number could be read
two ways, the calculator shows no card rather than guessing.

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
