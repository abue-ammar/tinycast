import Testing

@testable import Tinycast

extension CalcTests {
    @Test(
        arguments: [
            .display("20 percent of 50", "10"),
            .display("20 per cent of 50", "10"),
            .display("3 raised to 4", "81"),
            .display("3 raised to the power of 4", "81"),
            .display("2 exponent 10", "1,024"),
            .display("3 to the 4", "81"),
            .display("56 to the nearest 10", "60"),
            .display("squared root of 81", "9"),
            .display("cubed root of 27", "3"),
            .display("2 trillion", "2,000,000,000,000"),
            .copy("1.5 quadrillion", "1500000000000000"),
            .noResult("1 to the moon")
        ] as [Case])
    func spokenOperatorsAndMagnitudes(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("what is 20% of 50", "10"),
            .display("20% of 50?", "10"),
            .display("calculate 2 + 3", "5"),
            .display("what is 5 km in miles", "3.106855961 mi"),
            .noResult("what is"),
            .noResult("calculate")
        ] as [Case])
    func aQuestionAsksAboutWhatFollows(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("convert 5 km into miles", "3.106855961 mi"),
            .display("convert 10 kg to lb", "22.04622622 lb"),
            .display("convert 100 usd eur", "92.00 EUR"),
            .noResult("convert usd eur"),
            .display("5 km is what in miles", "3.106855961 mi"),
            .display("5 km is how many miles", "3.106855961 mi"),
            .display("how many feet in a mile", "5,280 ft"),
            .display("how many seconds are in a day", "86,400 s"),
            .display("seconds in 3 days", "259,200 s"),
            .display("cm in 5 inches", "12.7 cm"),
            .badges("how many feet in a mile", source: "Miles", target: "Feet"),
            .display("m in ft", "3.280839895 ft"),
            .display("feet in mile", "0.0001893939394 mi"),
            .display("exchange rate for usd to eur", "0.92 EUR"),
            .display("rate for eur to usd", "1.09 USD"),
            .noResult("how many"),
            .noResult("convert"),
            .noResult("xyz in a mile"),
            .noResult("rate my app")
        ] as [Case])
    func conversionsAskedInWords(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("remainder of 20 divided by 3", "2"),
            .badges("remainder of 20 divided by 3", source: "Expression", target: "Remainder"),
            .display("is 97 prime", "true"),
            .display("is 91 a prime number", "false"),
            .display("is prime 2", "true"),
            .display("is 9007199254740881 prime", "true"),
            .noResult("is 2.5 prime"),
            .noResult("is prime"),
            .noResult("prime video"),
            .display("clamp 20 between 5 and 15", "15"),
            .display("clamp 2 from 5 to 15", "5"),
            .display("clamp 10 5 15", "10"),
            .display("clamp 30 cm between 1 m and 2 m", "1 m"),
            .noResult("clamp 20 between 15 and 5"),
            .noResult("clamp"),
            .display("6 is to 600 as what is to 8", "0.08"),
            .display("6 is to 600 as 8 is to what", "800"),
            .display("6 to 600 as 8 to what", "800"),
            .display("2 km is to 4 km as what is to 10 kg", "5 kg"),
            .display("5 choose 3", "10"),
            .display("5 permutation 3", "60"),
            .display("3 combinations of 5", "10"),
            .display("3 permutations of 5", "60"),
            .badges("5 choose 3", source: "Expression", target: "Combinations"),
            .noResult("3 choose 5"),
            .display("logarithm 81 base 3", "4"),
            .display("logarithm of 20 to base 4", "2.160964047"),
            .display("log base 2 of 1024", "10"),
            .display("1000 is 10 to the power of what", "3"),
            .display("4 to what power is 64", "3"),
            .display("5 root of 32", "2"),
            .display("5 as multiplier of 1", "5x"),
            .display("5 is what multiplier of 1", "5x"),
            .display("5 as multiplier on 1", "4x"),
            .display("5 as multiplier off 10", "0.5x"),
            .display("10 to 20 as multiplier", "2x"),
            .noResult("10 to 20")
        ] as [Case])
    func spokenMath(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("median of 3, 1, 2", "2"),
            .display("median of 1, 2, 3 and 4", "2.5"),
            .display("count of 4, 8, 15, 16, 23, 42", "6"),
            .display("standard deviation of 2, 4, 4, 4, 5, 5, 7, 9", "2.138089935"),
            .display("std dev of 1, 2", "0.7071067812"),
            .display("sum of 1 km and 500 m", "1.5 km"),
            .display("midpoint of 2 and 32", "17"),
            .display("halfway between 2 and 32", "17"),
            .display("gcf of 20 and 30", "10"),
            .display("greatest common divisor of 20 and 30", "10"),
            .display("lowest common multiple of 4 and 6", "12"),
            .display("median(1, 5, 2, 8)", "3.5"),
            .display("median(3 km, 1 km, 2 km)", "2 km"),
            .badges("median of 3, 1, 2", source: "Expression", target: "Median"),
            .noResult("median"),
            .noResult("sum of")
        ] as [Case])
    func statisticsKeepTheirUnits(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("20% from 100", "20"),
            .display("take 20% off 100", "80"),
            .display("20% off of 100", "80"),
            .display("20% discount off $100", "80.00 USD"),
            .display("20% markup on 50", "60"),
            .display("15% tip on 42", "6.3"),
            .display("20% of what is 30", "150"),
            .display("20% off what is 30", "37.5"),
            .display("20% on what is 30", "25"),
            .display("what % is 25 of 100", "25%"),
            .display("10 is % of 20", "50%"),
            .display("10 is what % 20", "50%"),
            .display("10 as % 20", "50%"),
            .display("10 is what % with 20", "33.33333333%"),
            .display("10 as discount off 20", "50%"),
            .display("% change from 10 to 20", "100%"),
            .display("% increase from 10 to 20", "100%"),
            .display("% decrease from 20 to 10", "-50%"),
            .display("what % change is 10 to 20", "100%"),
            .display("15 as % after adding 3", "25%"),
            .display("15 is what % after +3", "25%"),
            .display("if 30 is 20%, what is 50%", "75"),
            .display("if 30 is 20% what is 60", "40%"),
            .display("if 20% is 30, what is 50%", "75"),
            .display("4 out of 10", "40%"),
            .display("10% tax on 100", "110"),
            .display("10% tax of 110", "11"),
            .display("10% tax in 110", "10"),
            .display("20% vat in 120", "20"),
            .display("10% sales tax on 100", "110"),
            .display("$100 + 10% tax", "110.00 USD"),
            .badges("20% vat in 120", source: "Expression", target: "Tax")
        ] as [Case])
    func percentPhrasings(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("round 56.2 up", "57"),
            .display("round 56.8 down", "56"),
            .display("round 56 up to nearest 10", "60"),
            .display("round 51 to next 10", "60"),
            .display("round 59 down to last 10", "50"),
            .display("round 56 up to 10", "60"),
            .display("round 56.789 to 1 digit", "56.8"),
            .display("round 3.14159 to 2 decimal points", "3.14"),
            .display("3.3 to nearest quarter", "3.25"),
            .display("round 3.14159 to nearest 8th", "3.125"),
            .display("0.75 to fraction", "3/4"),
            .display("0.375 as frac", "3/8"),
            .noResult("round 56 to 10"),
            .noResult("round up")
        ] as [Case])
    func roundingPhrasings(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1234567 to sci", "1.234567e6"),
            .display("0.000123 to scientific notation", "1.23e-4"),
            .display("-4500 to sci", "-4.5e3"),
            .copy("1234567 to sci", "1.234567e6"),
            .display("51.4772° to dms", "51° 28′ 37.92″"),
            .display("1 rad to dms", "57° 17′ 44.81″"),
            .display("5400 seconds to hms", "1h 30m 0s"),
            .display("1.5e3 to number", "1,500"),
            .display("2 to multiplier", "2x"),
            .display("255 to base 7", "513"),
            .display("35 to base 36", "Z"),
            .display("255 to base 16", "0xFF"),
            .badges("255 to base 7", source: "Decimal", target: "Base 7"),
            .display("90 min to laptime", "01:30:00"),
            .display("75.5 seconds to lap time", "00:01:15.5"),
            .display("440 hz to pitch", "A4"),
            .display("261.63 hz to pitch", "C4"),
            .display("1 khz to note", "B5"),
            .display("c4 to hz", "261.6255653 Hz"),
            .display("4° in nautical miles", "240 nmi"),
            .display("60 arcsec in nmi", "1 nmi"),
            .display("240 nmi in degrees", "4 deg"),
            .display("bb3 to hz", "233.0818808 Hz"),
            .noResult("a4 paper"),
            .display("1.75 as improper", "7/4"),
            .display("1.75 as mixed number", "1 3/4"),
            .display("0.5 as mixed", "1/2")
        ] as [Case])
    func numberFormsAndRadixes(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("speed of light in km/s", "299,792.458 km/s"),
            .badges("speed of light in km/s", source: "Speed Of Light", target: "Kilometers per Second"),
            .display("speed of light", "299,792,458 m/s"),
            .display("absolute zero in f", "-459.67 °F"),
            .display("boltzmann constant", "1.380649e-23 J/K"),
            .noResult("gravity falls"),
            .display("molar mass of C6H12O6", "180.156 g/mol"),
            .noResult("molar mass of"),
            .display("molar mass of CuSO4·5H2O", "249.677 g/mol"),
            .display("Ca(OH)2 molar mass", "74.092 g/mol"),
            .display("molar mass of CO2", "44.009 g/mol"),
            .display("molar mass of h2so4", "98.072 g/mol"),
            .noResult("molar mass of co2"),
            .noResult("molar mass of caco3"),
            .noResult("molar mass of sio2"),
            .display("molar mass of NaCl", "58.44 g/mol"),
            .noResult("molar mass of Xx2"),
            .noResult("molar mass of water"),
            .noResult("iron molar mass"),
            .noResult("molar mass of Carbon"),
            .noResult("100 gr to g"),
            .display("100 grains to g", "6.479891 g"),
            .display("5:00 min/km in km/h", "12 km/h"),
            .display("4:30 min/mi to km/h", "21.45792 km/h"),
            .display("first 10 characters of \"hello\"", "hello"),
            .display("last 2 words of \"one two three\"", "two three"),
            .display("length of \"hello world\"", "11"),
            .display("\"hello\" in uppercase", "HELLO"),
            .display("5\" to cm", "12.7 cm"),
            .noResult("5\" + 3\"x"),
            .display("100 eV to J", "1.602176634e-17 J"),
            .display("1 angstrom to nm", "0.1 nm"),
            .display("1 therm to kWh", "29.30011111 kWh"),
            .display("1 decade to years", "10 yr")
        ] as [Case])
    func constantsChemistryAndText(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("3000 px to inches at 300 ppi", "10 in"),
            .display("10 cm to px at 300 ppi", "1,181.102362 px"),
            .display("ppi of 27 inch display at 3840x2160", "163.1783089 ppi"),
            .display("ppi of 6.1 inch screen at 2532x1170", "457.2543463 ppi"),
            .noResult("10 kg to lb at 300 ppi")
        ] as [Case])
    func pixelsAgainstPhysicalSize(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1.75 m to feet and inches", "5 ft 8.897637795 in"),
            .display("1.75 m to ft in", "5 ft 8.897637795 in"),
            .display("2.5 kg to lb & oz", "5 lb 8.184904874 oz"),
            .display("100 months to years and months", "8 yr 4 mo"),
            .display("-1.5 ft to ft and in", "-1 ft 6 in"),
            .badges("1.75 m to feet and inches", source: "Meters", target: "Feet and Inches"),
            .noResult("5 km to kg and g")
        ] as [Case])
    func twoUnitsOfOneKind(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("$50/hr for 3 hours", "150.00 USD"),
            .display("60 km/h for 30 min", "30 km"),
            .display("$100,000/year for 3 months", "25,000.00 USD"),
            .display("download 20 GB at 10 MB/s", "33 min 20 s"),
            .display("transfer 1 TB at 100 Mbps", "22 hr 13 min 20 s"),
            .display("1 hour at 2x", "0.5 hr"),
            .display("90 min at 1.5× speed", "60 min"),
            .display("time saved 1 hour at 1.5x", "0.3333333333 hr"),
            .display("$50/hr is what per day", "1,200.00 USD/day"),
            .display("$50/hr as per week", "8,400.00 USD/week"),
            .display("60 km/h is how much per minute", "1 km/min"),
            .noResult("10 kg for 3 hours"),
            .noResult("download music"),
            .noResult("1 hour at 2")
        ] as [Case])
    func ratesTransfersAndPlaybackSpeeds(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("present value of $1000 after 5 years at 5%", "783.53 USD"),
            .display("500 invested 1000 returned", "100%"),
            .display("annual return on 500 invested 1000 returned after 5 years", "14.8698355%"),
            .display("annual return on 500 that grew to 1000 over 5 years", "14.8698355%"),
            .display("investment required for $50000/year at 4%", "1,250,000.00 USD"),
            .display("total interest on 10000 for 5 years at 6%", "1,599.680918"),
            .display("monthly interest on 10000 for 5 years at 6%", "26.66134863"),
            .display("20 after 5 years at 5% every year", "25.52563125"),
            .display("20 after 5 years at 5% decay every year", "15.47561875"),
            .display("20 after 10 years at 5% every 2 years", "25.52563125"),
            .display("time from 20 to 30 at 5% every year", "8.310386223 yr"),
            .display("time from 20 to 30 at 2 every day", "5 day"),
            .display("days from 20 to 30 at 2 every week", "35 day"),
            .display("growth every year from 20 to 30 over 5 years", "8.44717712%"),
            .noResult("100 for 5 years")
        ] as [Case])
    func growthAndFinance(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1 cup of flour in grams", "125 g"),
            .display("200 g butter in cups", "0.8810572687 cup"),
            .display("2 tbsp honey to g", "42.375 g"),
            .display("500 g all purpose flour in cups", "4 cup"),
            .display("density of honey", "1.432869212 g/cm³"),
            .display("olive oil density", "0.9129786129 g/cm³"),
            .badges("1 cup of flour in grams", source: "Flour", target: "Grams"),
            .display("1 cup to ml", "236.5882365 mL"),
            .noResult("1 cup of unicorn in grams"),
            .noResult("honey")
        ] as [Case])
    func ingredientsBetweenWeightAndVolume(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("days left in the year", "160 days").offline,
            .display("days left in 2026", "160 days").offline,
            .display("days remaining in this month", "7 days").offline,
            .display("hours left in today", "23.7 hours").offline,
            .display("workdays left in this month", "5 workdays").offline,
            .display("days in 2028", "366 days").offline,
            .display("weeks in 2026", "52.14285714 weeks").offline,
            .display("workdays in march", "22 workdays").offline,
            .display("days left in 2027", "365 days").offline,
            .badges("days left in 2026", source: "2026", target: "Remaining").offline,
            .noResult("days left in 2025").offline,
            .noResult("days left").offline,
            .display("week of month", "4").offline,
            .display("day of the month on dec 25", "25").offline
        ] as [Case])
    func countsOverAPeriod(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("whole weeks between jan 1 and mar 1", "8 weeks").offline,
            .display("from jan 1 through jan 31", "31 days").offline,
            .display("week of year", "30").offline,
            .display("halfway between jan 1 and mar 1", "31 January").offline,
            .display("midpoint between jan 1 2026 and dec 31 2026", "2 July").offline,
            .display("halfway between 9am and 5pm", "24 July at 1:00 PM").offline,
            .display("previous friday", "17 July").offline,
            .display("this friday", "24 July").offline,
            .display("this sunday", "26 July").offline,
            .display("tomorrow at midday", "25 July at 12:00 PM").offline,
            .display("5 p.m. + 2 hours", "24 July at 7:00 PM").offline,
            .display("days until xmas", "154 days").offline,
            .display("days until nye", "160 days").offline,
            .display("easter 2027", "28 March, 2027").offline,
            .display("easter 2038", "25 April, 2038").offline,
            .display("good friday 2027", "26 March, 2027").offline,
            .display("easter monday 2027", "29 March, 2027").offline,
            .display("orthodox easter 2027", "2 May, 2027").offline,
            .display("chinese new year 2027", "6 February, 2027").offline,
            .display("ramadan 2027", "8 February, 2027 (±1 day)").offline,
            .copy("ramadan 2027", "8 February, 2027").offline,
            .display("end of ramadan 2027", "8 March, 2027 (±1 day)").offline,
            .display("eid al-fitr 2027", "9 March, 2027 (±1 day)").offline,
            .display("eid ul fitr 2027", "9 March, 2027 (±1 day)").offline,
            .display("eid al-adha 2027", "16 May, 2027 (±1 day)").offline,
            .display("eid-ul-azha 2027", "16 May, 2027 (±1 day)").offline,
            .display("eid al-fitr 2033", "3 January, 2033 (±1 day)").offline,
            .display("days until eid al-adha", "296 days (±1 day)").offline,
            .copy("days until eid al-adha", "296 days").offline,
            .display("weekday on eid al-adha 2027", "Sunday (±1 day)").offline,
            .badges("eid al-adha 2027", source: "Friday, 24 July", target: "Sunday").offline,
            .noResult("eid").offline,
            .display("hanukkah 2026", "4 December").offline,
            .display("end of hanukkah 2026", "12 December").offline,
            .display("days until easter", "247 days").offline,
            .display("days until boxing day", "155 days").offline,
            .noResult("easter").offline,
            .noResult("easter egg").offline,
            .noResult("good friday").offline,
            .display("new timestamp", "1,784,852,280").offline,
            .display("now to iso", "2026-07-24T00:18:00+00:00").offline,
            .display("today + 3 days to iso8601", "2026-07-27T00:00:00+00:00").offline
        ] as [Case])
    func spansAndNamedDays(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("date in tokyo", "Friday, 24 July").offline,
            .display("tokyo date", "Friday, 24 July").offline,
            .display("local time in tokyo", "9:18 AM").offline,
            .display("tokyo local time", "9:18 AM").offline,
            .display("time now in tokyo", "9:18 AM").offline,
            .display("time in tokyo now", "9:18 AM").offline,
            .display("time difference between london and tokyo", "9:18 AM (+8h)").offline,
            .display("diff london & tokyo", "9:18 AM (+8h)").offline,
            .display("diff london tokyo", "9:18 AM (+8h)").offline,
            .display("diff new york and san francisco", "5:18 PM (-3h)").offline,
            .display("time in tokyo when it's 5pm in london", "1:00 AM (tomorrow)").offline,
            .display("what time is it in tokyo when it is 9am in new york", "10:00 PM").offline,
            .noResult("local time").offline,
            .noResult("when it's 5pm").offline
        ] as [Case])
    func zonesAskedInWords(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(
        arguments: [
            .display("1 parsec to light years", "3.261563777 ly"),
            .display("1 au to km", "149,597,870.7 km"),
            .display("10 fathoms to m", "18.288 m"),
            .display("1 furlong to m", "201.168 m"),
            .display("1 metric cup to ml", "250 mL"),
            .display("5 microliters to ml", "0.005 mL"),
            .display("1 cubic mile to cubic km", "4.168181825 km³"),
            .display("1 barrel to l", "158.9872949 L"),
            .display("1 imperial tablespoon to ml", "17.75816406 mL"),
            .display("1 troy ounce to g", "31.1034768 g"),
            .display("1 carat to g", "0.2 g"),
            .display("1 twh to gwh", "1,000 GWh"),
            .display("1 ksi to psi", "1,000 psi"),
            .display("100 rpm to rad/s", "10.47197551 rad/s"),
            .display("1 farad to microfarads", "1,000,000 µF"),
            .display("1 tesla to gauss", "10,000 G"),
            .display("10 newton meters to pound feet", "7.375621493 lb·ft"),
            .display("2 mol + 500 mmol", "2,500 mmol"),
            .display("12 V * 2 s", "24 Wb"),
            .display("1 microfarad * 1 kiloohm", "0.001 s"),
            .display("1 exabyte to petabytes", "1,000 PB"),
            .error("10 Nm to J", "Cannot convert Torque to Energy."),
            .display("100 F to C", "37.77777778 °C"),
            .display("5 H to hours", "5 hr"),
            .display("10 nm to m", "1e-08 m"),
            .display("5 lb in kg", "2.26796185 kg")
        ] as [Case])
    func wordedUnits(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }
}
