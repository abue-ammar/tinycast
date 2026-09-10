// Standalone test for the calculator engine, compiling the real Foundation-only sources.
import Foundation

@main
@MainActor
struct CalcTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        // Arithmetic & precedence
        expectDisplay("2+2", "4")
        expectDisplay("5*7", "35")
        expectDisplay("100/4", "25")
        expectDisplay("2^10", "1,024")
        expectDisplay("2^3^2", "512")  // right-associative
        expectDisplay("2 square root of 9", "6")
        expectDisplay("square root of 25m2", "5 m")
        expectDisplay("cube root of -8m3", "-2 m")
        expectDisplay("cube root of 8%", "0.430886938")
        expectDisplay("cube root of -8%", "-0.430886938")
        expectDisplay("2 * (3 + 4) << 1", "28")
        expectDisplay("1 ≤ 2", "true")
        expectDisplay("2 ≠ 3", "true")
        expectDisplay("2 ⊻ 3", "1")
        expectDisplay("1µs to ns", "1,000 ns")
        expectDisplay("1μs to ns", "1,000 ns")
        expectDisplay("2\u{00A0}+\u{2009}2", "4")
        expectError("10 colo\u{0301}n to usd", "No exchange rate for CRC.")
        expectCopy("-9007199254740992 + 0", "-9007199254740992")
        expectCopy("-0 * 1234", "0")
        expectExpression("10k +", "10k +")
        expectExpression("45+", "45+")
        expectExpression("(2)+", "(2)+")
        expectDisplay("2m / 2m to hex", "0x1")
        expectDisplay(String(repeating: "1+", count: 100) + "1", "101")
        expectNil(String(repeating: "1+", count: 128) + "1")
        expectDisplay("2**2", "4")  // "**" is an alias for "^" (Python/JS/shell spelling)
        expectDisplay("2**10", "1,024")
        expectDisplay("2**3**2", "512")  // right-associative, same as "^"
        expectDisplay("(5+2)*3", "21")
        expectDisplay("5!", "120")
        expectDisplay("3!!", "720")  // (3!)! — chained postfix
        expectDisplay("-5+3", "-2")
        expectDisplay("-2^2", "-4")  // unary minus binds looser than ^
        expectDisplay("10/4", "2.5")
        expectDisplay("1/3", "0.3333333333")
        expectDisplay("2.5 * 4", "10")
        expectDisplay("1,000 + 234", "1,234")  // grouping commas accepted in input

        // Compact thousands suffix — attached `k` is a number suffix; spaced `k` remains Kelvin
        expectDisplay("10k", "10,000")
        expectCopy("10k", "10000")
        expectDisplay("2.5K", "2,500")
        expectDisplay("10k + 500", "10,500")
        expectDisplay("10k * 2", "20,000")
        expectBadges("10k", source: "Expression", target: "Result")

        // Scientific notation input
        expectDisplay("1e6 + 1", "1,000,001")
        expectDisplay("1.5e-3 * 2", "0.003")
        expectDisplay("2.5e8 / 2", "125,000,000")
        expectDisplay("1E6 + 1", "1,000,001")  // uppercase E
        expectDisplay("1e6", "1,000,000")  // a lone shorthand literal cards like "10k"
        expectNil("10em")  // partial "e" isn't an exponent, so the ident scanner still gets it
        expectDisplay("1e3k + 1", "1,000,001")  // exponent then compact suffix, both applied

        // Exact up to 2^53, past the old 1e15 cutoff — truncating these lost real digits on copy
        expectDisplay("2^49", "562,949,953,421,312")
        expectDisplay("2^50", "1,125,899,906,842,624")
        expectCopy("2^50", "1125899906842624")
        expectDisplay("999999999999999 + 1", "1,000,000,000,000,000")  // exactly the old cutoff
        // Beyond 2^53 the precision is genuinely gone, so exponent form is the honest answer
        expectDisplay("123456789 * 123456789", "1.524157875e+16")

        // Functions
        expectDisplay("sqrt(64)", "8")
        expectDisplay("sqrt 64", "8")
        expectDisplay("sqrt 64 + 36", "44")  // bare arg is one operand: sqrt(64) + 36
        expectDisplay("log(1000)", "3")
        expectDisplay("ln(e)", "1")
        expectDisplay("sin(30deg)", "0.5")
        expectDisplay("cos(60deg)", "0.5")
        expectDisplay("tan(45deg)", "1")
        expectDisplay("sin(pi/2)", "1")
        expectDisplay("abs(-4)", "4")
        expectDisplay("floor(2.7)", "2")
        expectDisplay("ceil(2.1)", "3")
        expectDisplay("round(2.5)", "3")
        expectDisplay("SQRT(64)", "8")  // case-insensitive

        // Constants
        expectDisplay("2*pi", "6.283185307")
        expectDisplay("π*2", "6.283185307")
        expectDisplay("e^2", "7.389056099")

        // Implicit multiplication
        expectDisplay("4(2+3)", "20")
        expectDisplay("(2+3)(2+3)", "25")
        expectDisplay("2pi", "6.283185307")
        expectDisplay("2π", "6.283185307")
        expectDisplay("2sqrt(9)", "6")
        expectDisplay("2(3+1)+1", "9")  // implicit "*" binds like explicit "*", not looser
        expectDisplay("10π ^e", "224.5915772")  // and looser than "^"
        expectDisplay("3x3", "9")
        expectDisplay("3 x 3", "9")
        expectDisplay("3X3", "9")
        expectDisplay("3 x -2", "-6")
        expectDisplay("2xpi", "6.283185307")
        expectDisplay("6/2x(1+2)", "9")
        expectDisplay("10 x", "10")
        expectDisplay("$5 x 2", "10.00 USD")
        expectNil("x")
        expectNil("x3")
        expectNil("3x")
        // Juxtaposition against a bracket carries the unit through, matching explicit "*"
        expectDisplay("2(3)kg", "6 kg")
        expectDisplay("2*(3)kg", "6 kg")
        expectDisplay("2(3)kg x 2", "12 kg")

        // Scientific notation — only when the exponent hugs the mantissa
        expectDisplay("1e5", "100,000")
        expectDisplay("2e10", "20,000,000,000")
        expectDisplay("1E5", "100,000")
        expectDisplay("1.5e3", "1,500")
        expectDisplay("3e+2", "300")
        expectCopy("1e-5", "1e-05")
        expectDisplay("2e10/2", "10,000,000,000")
        expectDisplay("1e5 to hex", "0x186A0")
        expectDisplay("5e-3km", "0.003106855961 mi")
        expectDisplay("2e", "5.436563657")  // no digits after "e" — still 2 × Euler's e
        expectDisplay("1 e", "2.718281828")  // detached — never an exponent
        expectNil("1e400")  // overflows to infinity, so not calculator input
        expectNil("1e308k")
        expectNil("-1e308k")
        expectNil("1e308k to hex")
        expectNil("1e308 * 2 > 1")
        expectNil("1e308m + 1e308m > 0m")
        expectNil("1e308m == 1e308km")
        expectNil("(1e308 * 2) ^ 0")
        expectDisplay("1e305k", "1e+308")
        expectNil("1e5e5")

        // Percent
        expectDisplay("20% of 450", "90")
        expectDisplay("450 + 20%", "540")
        expectDisplay("450 - 15%", "382.5")
        expectDisplay("20%", "0.2")

        // Modulo — spelled out, so it never competes with the percent cases above
        expectDisplay("10 mod 3", "1")
        expectDisplay("17 mod 5", "2")
        expectDisplay("10k mod 3", "1")
        expectDisplay("-10 mod 3", "-1")  // fmod semantics: the sign follows the dividend
        expectDisplay("2 + 10 mod 3", "3")  // same precedence as * and /, binds tighter than +
        expectNil("10 mod 0")
        expectNil("10 % 3")  // "%" stays percent, whatever follows it
        expectDisplay("450 + 20% - 5", "535")

        // Unit conversion — length / weight / temperature / time / area / volume / storage
        expectDisplay("10km to mi", "6.213711922 mi")
        expectDisplay("10 km in miles", "6.213711922 mi")
        expectDisplay("5ft in cm", "152.4 cm")
        expectDisplay("1 m to ft", "3.280839895 ft")
        expectDisplay("10 cm in in", "3.937007874 in")
        expectDisplay("10 in in cm", "25.4 cm")  // first "in" is the unit, second the connector
        expectDisplay("16 oz to lb", "1 lb")
        expectDisplay("2.2 lbs to kg", "0.997903214 kg")
        expectDisplay("100 C to F", "212 °F")
        expectDisplay("32F to C", "0 °C")
        expectDisplay("273.15K to C", "0 °C")  // attached Kelvin remains valid in a conversion
        expectDisplay("273.15 K to C", "0 °C")
        expectDisplay("10 k to c", "-263.15 °C")
        expectDisplay("0 F to C", "-17.77777778 °C")
        expectDisplay("300 K to C", "26.85 °C")
        expectDisplay("90min to hr", "1.5 hr")
        expectDisplay("2hr to min", "120 min")
        expectDisplay("1day to sec", "86,400 s")
        expectDisplay("1 week to hr", "168 hr")
        expectDisplay("2 acre to m2", "8,093.712845 m²")
        expectDisplay("1 m² to ft²", "10.76391042 ft²")
        expectDisplay("2L -> mL", "2,000 mL")
        expectDisplay("1 cup to tbsp", "16 tbsp")
        expectDisplay("1 gal to L", "3.785411784 L")
        expectDisplay("1 GiB to MB", "1,073.741824 MB")
        expectDisplay("1 GB to MiB", "953.6743164 MiB")
        expectDisplay("8 bit to byte", "1 B")
        expectDisplay("2*5 km to mi", "6.213711922 mi")  // expression on the left side

        // Number bases
        expectBadges("0b1010", source: "Binary", target: "Decimal")
        expectBadges("0o17", source: "Octal", target: "Decimal")
        expectBadges("0B1010 +", source: "Binary", target: "Decimal")
        expectBadges("0O17 +", source: "Octal", target: "Decimal")
        expectCopy("1.00000000004m to pm +", "1000000000040 pm")
        expectCopy("1.00000000004m to pm **", "1000000000040 pm")
        expectCopy("1.00000000004m to pm + =", "1000000000040 pm")
        expectCopy("1.00000000004m to pm + +", "1000000000040 pm")
        expectCopy("1.00000000004 * 1e12 to hex +", "0xE8D4A51028")
        expectDisplay("255 to hex", "0xFF")
        expectDisplay("255 to binary", "0b11111111")
        expectDisplay("0xff to decimal", "255")
        expectDisplay("0b1010 to decimal", "10")
        expectDisplay("255 to octal", "0o377")
        expectDisplay("0xff", "255")  // bare radix literal echoes decimal

        // Friendly category errors
        expectError("10kg to sec", "Cannot convert Weight to Time.")
        expectError("100 mL to km", "Cannot convert Volume to Length.")
        expectError("1 GB to hr", "Cannot convert Digital Storage to Time.")

        // Non-calculator input → no card
        expectNil("safari")
        expectNil("1password")
        expectNil("45")
        expectNil("3.14")
        expectNil("pi")
        expectNil("e")
        expectNil("10km to")  // half-typed conversion
        expectNil("10 to mi")
        expectDisplay("45+", "45")  // safe trailing operators keep the last complete result
        expectNil("sqrt()")
        expectNil("2.5!")  // factorial needs an integer
        expectNil("")

        expectDisplay("hypot(3,4)", "5")
        expectDisplay("2hypot(3,4)", "10")
        expectDisplay("round(3.14159,2)", "3.14")
        expectDisplay("round(1234,-2)", "1,200")
        expectDisplay("log(8,2)", "3")
        expectDisplay("gcd(12,18,8)", "2")
        expectDisplay("lcm(4,6)", "12")
        expectDisplay("atan2(1,1)*4", "3.141592654")
        expectDisplay("root(-8,3)", "-2")
        expectDisplay("hypot(3m,400cm)", "5 m")
        expectDisplay("min(1km,999m)", "0.999 km")
        expectDisplay("sum(1km,500m)", "1.5 km")
        expectDisplay("round(2.567km,1)", "2.6 km")
        expectError("min(1km,1hr)", "Cannot compare values with different dimensions.")
        expectNil("gcd(1.5,2)")
        expectNil("lcm(9223372036854775807,2)")
        expectNil("round(1,9999)")
        expectDisplay("1 << 8", "256")
        expectDisplay("256 >> 2", "64")
        expectDisplay("6 & 3", "2")
        expectDisplay("5 xor 3", "6")
        expectDisplay("~1", "-2")
        expectDisplay("1 | 2 == 3", "true")
        expectDisplay("~1 == -2", "true")
        expectDisplay("1km == 1000m", "true")
        expectDisplay("30min >= 1hr", "false")
        expectNil("1 << 64")
        expectNil("1 << -1")
        expectNil("1 << 63")
        expectNil("9007199254740993 & 1")
        expectNil("0x20000000000001 & 1")
        expectDisplay("5 mod 2 == 1", "true")
        expectExpression("1 << 8 == 256", "1 << 8 == 256")
        expectNil("(1 == 1)kg")
        expectNil("-(1 == 1)")
        expectNil("sqrt(1 == 1)")

        // Formatting: display grouped, copyText plain
        expectDisplay("1234567*1", "1,234,567")
        expectCopy("1234567*1", "1234567")
        expectCopy("10km to mi", "6.213711922 mi")
        expectDisplay("-1234.5-0.25", "-1,234.75")

        // Card expression echo
        expectExpression("3*3", "3×3")
        expectExpression("10km to mi", "10 km")

        // Badges on explicit conversions
        expectBadges("10km to mi", source: "Kilometers", target: "Miles")
        expectBadges("100 C to F", source: "Celsius", target: "Fahrenheit")

        // Bare-unit auto-conversion (no connector)
        expectDisplay("1m", "3 feet 3.37007874 inches")
        expectExpression("1m", "1 m")
        expectBadges("1m", source: "Meters", target: "Feet")
        expectDisplay("1hr", "60 min")
        expectBadges("1hr", source: "Hours", target: "Minutes")
        expectDisplay("5ft", "1.524 m")
        expectDisplay("100g", "3.527396195 oz")
        expectDisplay("2*3 kg", "6 kg")  // an operator keeps the answer in the units written
        expectDisplay("20 celsius", "68 °F")
        expectDisplay("50cm", "19.68503937 in")
        // Ambiguous single-letter aliases stay app searches, not bare temperatures
        expectNil("5 k")
        expectNil("100 c")
        expectNil("32f")

        // Unit expressions — addition/subtraction converts the RHS and keeps the leftmost unit
        expectDisplay("10kg + 5kg", "15 kg")
        expectCopy("10kg + 5kg", "15 kg")
        expectExpression("10kg + 5kg", "10 kg + 5 kg")
        // Signs, parens and postfix % hug their operand instead of floating as separate words
        expectExpression("10kg * 3%", "10 kg × 3%")
        expectExpression("(10kg + 5kg) * 3%", "(10 kg + 5 kg) × 3%")
        expectExpression("-5kg + 2kg", "-5 kg + 2 kg")
        expectExpression("5 feet 3 inches", "5 ft 3 in")
        // A function keeps its bracket, and a word operator keeps the sign on the operand it leads
        expectExpression("hypot(3m,400cm)", "hypot(3 m, 400 cm)")
        expectExpression("min(1km,999m)", "min(1 km, 999 m)")
        expectExpression("round(2.567km,1)", "round(2.567 km, 1)")
        expectExpression("2*sqrt(9)m", "2 × sqrt(9) m")
        expectExpression("cube root of -8m3", "cube root of -8 m³")
        expectExpression("15% of -2kg", "15% of -2 kg")
        expectExpression("10kg - 5kg", "10 kg - 5 kg")
        expectExpression("2 * 5feet 3inches", "2 × 5 ft 3 in")
        expectBadges("10kg + 5kg", source: "Expression", target: "Kilograms")
        expectDisplay("10kg + 10g", "10,010 g")  // issue #64, answered in the last unit typed
        expectDisplay("10kg + 500g", "10,500 g")
        expectDisplay("500g + 1kg", "1.5 kg")
        expectCopy("500g + 1kg", "1.5 kg")
        expectDisplay("10lb + 5kg", "9.5359237 kg")
        expectDisplay("1m + 50cm", "150 cm")
        expectDisplay("2hr + 30min", "150 min")
        expectDisplay("1GiB + 512MiB", "1,536 MiB")
        expectDisplay("1L - 250mL", "750 mL")
        expectDisplay("-5kg + 2kg", "-3 kg")
        expectDisplay("-(2kg + 500g)", "-2,500 g")
        expectDisplay("10 pounds + 5 pounds", "15 lb")  // unit wins the currency collision
        expectDisplay("1m² + 10ft²", "20.76391042 ft²")
        expectDisplay("1L + 1cup", "5.226752838 cup")
        expectDisplay("1GB + 1GiB", "1.931322575 GiB")
        expectDisplay("90deg + 1rad", "2.570796327 rad")
        expectDisplay("60mph + 10kmh", "106.56064 km/h")
        expectDisplay("1bar + 10psi", "24.50377377 psi")
        expectDisplay("1Gbps + 500Mbps", "1,500 Mbps")

        // Unit-expression precedence, parentheses, scalar operations, and cancellation
        expectDisplay("10kg + 2 * 5kg", "20 kg")
        expectDisplay("(10kg + 5kg) * 2", "30 kg")
        expectDisplay("2 * (3kg + 500g)", "7,000 g")
        expectDisplay("20kg / 2 + 3kg", "13 kg")
        expectDisplay("20kg / (2 + 3)", "4 kg")
        expectDisplay("5kg * 3", "15 kg")
        expectDisplay("10kg / 4", "2.5 kg")
        expectDisplay("5kg / 2kg", "2.5")
        expectBadges("5kg / 2kg", source: "Expression", target: "Result")
        expectDisplay("5kg / 500g", "10")
        expectDisplay("1kg / 3", "0.3333333333 kg")
        expectDisplay("10kg * (2 + 3)", "50 kg")
        expectDisplay("10kg / (2 * 5)", "1 kg")
        expectDisplay("(10kg * 3) / 5kg", "6")
        expectDisplay("10kg / (5kg / 2)", "4")
        expectDisplay("(2kg + 500g) * 4", "10,000 g")
        expectDisplay("(20kg - 5kg) / 3", "5 kg")

        // Percentages carry through quantity arithmetic
        expectDisplay("10kg + 20%", "12 kg")
        expectDisplay("10kg - 20%", "8 kg")
        expectDisplay("10kg * 20%", "2 kg")
        expectDisplay("10kg * 3%", "0.3 kg")
        expectDisplay("3% * 10kg", "0.3 kg")
        expectDisplay("10kg * 0%", "0 kg")
        expectDisplay("10kg * -3%", "-0.3 kg")
        expectDisplay("10kg / 25%", "40 kg")
        expectDisplay("10kg / 200%", "5 kg")
        expectDisplay("10kg * 3% + 1kg", "1.3 kg")
        expectDisplay("(10kg + 5kg) * 3%", "0.45 kg")
        expectDisplay("10kg * 3% to g", "300 g")
        expectCopy("10kg * 3% to g", "300 g")
        expectDisplay("20% of (10kg + 5kg)", "3 kg")
        expectDisplay("3% of 10kg", "0.3 kg")
        expectNil("10kg / 0%")
        expectDisplay("19m + 47%", "27.93 m")  // documented Raycast behavior

        // Incomplete expressions retain the last complete, actionable result
        expectDisplay("10 +", "10")
        expectDisplay("10 -", "10")
        expectDisplay("10 *", "10")
        expectDisplay("10 /", "10")
        expectDisplay("10 ^", "10")
        expectDisplay("10k +", "10,000")
        expectCopy("10k +", "10000")
        expectDisplay("10kg *", "10 kg")
        expectDisplay("10kg + 500g +", "10,500 g")
        expectDisplay("(10kg + 500g) *", "10,500 g")
        expectDisplay("10kg * 3% +", "0.3 kg")
        expectDisplay("20% of 450 +", "90")
        expectBadges("10 +", source: "Expression", target: "Result")
        expectBadges("10kg *", source: "Expression", target: "Kilograms")
        expectNil("+")
        expectNil("10 + nonsense")
        expectNil("10 + (")
        expectNil("10 of")  // a stray English word is a search, not a partial expression

        // A partial after a conversion echoes the typed text, and keeps the source radix / units
        expectExpression("10km to mi *", "10km to mi ×")
        expectDisplay("10km to mi *", "6.213711922 mi")
        expectExpression("255 to hex +", "255 to hex +")
        expectBadges("0xff -", source: "Hexadecimal", target: "Decimal")
        expectDisplay("0xff -", "255")

        // A conversion suffix applies to the complete unit expression
        expectDisplay("(1kg + 500g) to lb", "3.306933933 lb")
        expectDisplay("10kg + 500g to lb", "23.14853753 lb")
        expectDisplay("(10lb + 5kg) to kg", "9.5359237 kg")
        expectDisplay("(1m + 50cm) to ft", "4.921259843 ft")
        expectBadges("(1kg + 500g) to lb", source: "Expression", target: "Pounds")
        expectError("(1kg + 500g) to m", "Cannot convert Weight to Length.")

        // Composite reads as one quantity in its leading unit; an operator answers in the last.
        expectDisplay("5 feet 3 inches to cm", "160.02 cm")
        expectDisplay("5 feet 3 inches", "5.25 ft")
        expectDisplay("1hr 30min", "1.5 hr")
        expectDisplay("5feet + 1m", "2.524 m")
        expectBadges("5feet + 1m", source: "Expression", target: "Meters")
        expectDisplay("1kg + 500g + 2lb", "5.306933933 lb")  // chained: the last unit wins
        expectDisplay("2 * 5kg", "10 kg")
        expectDisplay("3 * 2m", "6 m")

        // Affine temperatures only combine in the same unit; mixed absolute scales are ambiguous
        expectDisplay("20 celsius + 10 celsius", "30 °C")
        expectDisplay("68 fahrenheit - 32 fahrenheit", "36 °F")
        expectError(
            "20 celsius + 50 fahrenheit",
            "Cannot combine temperatures with different units.")

        // Clear dimensional mistakes are errors; incomplete or non-finite input stays silent
        expectError("1kg + 1m", "Cannot add Weight and Length.")
        expectError("1kg + 1hr", "Cannot add Weight and Time.")
        // A bare number written against a quantity takes its unit
        expectDisplay("1kg + 1", "2 kg")
        expectDisplay("10kg + 5", "15 kg")
        expectDisplay("5kg+5", "10 kg")
        expectDisplay("5 + 10kg", "15 kg")
        expectDisplay("$10 + 5", "15.00 USD")
        expectBadges("5kg+5", source: "Expression", target: "Kilograms")
        expectDisplay("10kg + -20%", "9.8 kg")  // unary minus drops percent, as in `450 + -20%`
        // Adjacency differs: a bare number there is a unit still being typed.
        expectNil("1hr 30")  // mid-way through "1hr 30min"
        expectNil("5 feet 3")  // mid-way through "5 feet 3 inches"
        expectDisplay("1kg * 1m", "1 kg·m")
        expectDisplay("1cm/m", "0.01")
        expectDisplay("sqrt(4m) to cm^0.5", "20 cm^0.5")
        expectDisplay("1 kg/m3 to g/cm3", "0.001 g/cm³")
        expectDisplay("10m * 2s to cm*s", "2,000 cm·s")
        expectDisplay("2kg / 4m3", "0.5 kg/m³")
        expectDisplay("1kg/m3 + 1g/cm3", "1.001 g/cm³")
        expectDisplay("100 USD / 4hr", "25 USD/hr")
        expectDisplay("25 USD/hr * 8hr", "200.00 USD")
        expectDisplay("8hr * 25 USD/hr", "200.00 USD")
        expectDisplay("25 USD/hr to EUR/min", "0.3833333333 EUR/min")
        expectDisplay("25 USD/hr / 23 EUR/hr", "1")
        expectErrorWithoutRates("25 USD/hr to EUR/hr", "Exchange rates unavailable — check your connection.")
        expectError("2 celsius * 3m", "Multiplication of these unit values is not supported.")
        expectDisplay("1 / 1kg", "1 kg^-1")
        expectDisplay("(2m)^2", "4 m²")
        expectDisplay("5m * 4m to ft2", "215.2782083 ft²")
        expectDisplay("2m * 30cm", "0.6 m²")
        expectDisplay("2m * 3m * 4m to l", "24,000 L")
        expectDisplay("1 ft³ to l", "28.31684659 L")
        expectDisplay("1m3", "1,000 L")
        expectDisplay("1cm3", "1 mL")
        expectDisplay("1dm³ to l", "1 L")
        expectDisplay("(2dm)^3 to l", "8 L")
        expectDisplay("1dL to cl", "10 cL")
        expectDisplay("3 * 2cl 5ml to ml", "75 mL")
        expectDisplay("1 fl oz to ml", "29.57352956 mL")
        expectDisplay("250ml to fl oz", "8.453505675 fl oz")
        expectDisplay("2m * 30cm * 40cm to l", "240 L")
        expectDisplay("pi * (10cm)^2 * 30cm to l", "9.424777961 L")
        expectDisplay("4/3 * pi * (10cm)^3 to l", "4.188790205 L")
        expectDisplay("500l / (2m * 1m) to cm", "25 cm")
        expectDisplay("cbrt(8l) to cm", "20 cm")
        expectDisplay("10l / 2min to l/min", "5 L/min")
        expectDisplay("10l/min * 30s to l", "5 L")
        expectDisplay("150l / 10l/min to duration", "15 min")
        expectDisplay("1m³/h to l/min", "16.66666667 L/min")
        expectDisplay("60l/min to m3/h", "3.6 m³/h")
        expectDisplay("2gpm to l/min", "7.570823568 L/min")
        expectError("10l + 2l/min", "Cannot add Volume and Volume Flow Rate.")
        expectNil("1m3/x")
        expectDisplay("100 Mbps to MB/s", "12.5 MB/s")
        expectDisplay("1 MiB/s to Mbps", "8.388608 Mbps")
        expectDisplay("1GB / 10MB/s to s", "100 s")
        expectDisplay("8kbit to B", "1,000 B")
        expectDisplay("1um to nm", "1,000 nm")
        expectDisplay("1 GHz to MHz", "1,000 MHz")
        expectDisplay("500 microseconds to ms", "0.5 ms")
        expectDisplay("1ton to kg", "1,000 kg")
        expectDisplay("1stone to kg", "6.35029318 kg")
        expectDisplay("1nmi to km", "1.852 km")
        expectDisplay("1ukgal to l", "4.54609 L")
        expectDisplay("1ukpint to ml", "568.26125 mL")
        expectDisplay("100hp to kw", "74.56998716 kW")
        expectDisplay("3000rpm to hz", "50 Hz")
        expectDisplay("1btu to kj", "1.055055853 kJ")
        expectDisplay("1lbf to n", "4.448221615 N")
        expectDisplay("3000px / 300ppi to inches", "10 in")
        expectDisplay("5in * 300PPI", "1,500 px")
        expectCopy("5in * 300ppi", "1500 px")
        expectDisplay("300ppi * 5in", "1,500 px")
        expectDisplay("3000 pixels / 10in to ppi", "300 ppi")
        expectBadges("3000px / 10in", source: "Expression", target: "Pixels per Inch")
        expectDisplay("3000px / 300px/in to cm", "25.4 cm")
        expectDisplay("300ppi to px/cm", "118.1102362 px/cm")
        expectDisplay("100px/cm to ppi", "254 ppi")
        expectDisplay("1px/mm to ppi", "25.4 ppi")
        expectDisplay("100px/m * 1m", "100 px")
        expectDisplay("300ppi", "118.1102362 px/cm")
        expectDisplay("1920px * 1080px", "2,073,600 px²")
        expectDisplay("sqrt(9px²)", "3 px")
        expectDisplay("sqrt((3840px)^2 + (2160px)^2) / 27in", "163.1783089 ppi")
        expectDisplay("(300ppi * 2.54cm) / 300px", "1")
        expectError("3000px to cm", "Cannot convert Pixels to Length.")
        expectError("10px + 1in", "Cannot add Pixels and Length.")
        expectNil("3000px / 0ppi")
        expectNil("pixels")
        expectDisplay("20m2 / 4m", "5 m")
        expectDisplay("sqrt(25m2)", "5 m")
        expectDisplay("cbrt(-8m3)", "-2 m")
        expectDisplay("pi * (2m)^2 to m2", "12.56637061 m²")
        expectDisplay("sin(30deg) * 10m", "5 m")
        expectDisplay("100km / 2h to km/h", "50 km/h")
        expectDisplay("90km/h * 20min to km", "30 km")
        expectDisplay("100km / 50km/h to h", "2 hr")
        expectDisplay("1GB / 100mbps to s", "80 s")
        expectDisplay("1500w * 2h to kwh", "3 kWh")
        expectDisplay("5 watt * 3h 30min", "17.5 Wh")
        expectDisplay("3h 30min * 5 watt", "17.5 Wh")
        expectDisplay("5 watt * 3h 30min to kwh", "0.0175 kWh")
        expectDisplay("5 watt * 3h 30min to j", "63,000 J")
        expectCopy("5 watt * 3h 30min", "17.5 Wh")
        expectDisplay("5w * 3h 30min + 2wh", "19.5 Wh")
        expectDisplay("2kw * 3h 30min", "7 kWh")
        expectDisplay("5w * 30s", "150 J")
        expectDisplay("12V * 2A", "24 W")
        expectDisplay("12V / 6ohm", "2 A")
        expectDisplay("12V / 2A", "6 Ω")
        expectDisplay("2A * 6Ω", "12 V")
        expectDisplay("24W / 12V", "2 A")
        expectDisplay("500mA * 3h 30min", "1,750 mAh")
        expectDisplay("2000mAh / 500mA to hours", "4 hr")
        expectDisplay("12V * 2Ah to wh", "24 Wh")
        expectDisplay("10Wh / 5V to mah", "2,000 mAh")
        expectDisplay("3600 coulombs to ah", "1 Ah")
        expectDisplay("1mW to W", "0.001 W")
        expectDisplay("500mA", "0.5 A")
        expectDisplay("1MW to W", "1,000,000 W")
        expectDisplay("1MWh to kwh", "1,000 kWh")
        expectDisplay("1mΩ to ohm", "0.001 Ω")
        expectDisplay("1MΩ to ohm", "1,000,000 Ω")
        expectDisplay("2 * 5feet 3inches", "10.5 ft")
        expectDisplay("90km / 1h 30min to km/h", "60 km/h")
        expectDisplay("2 * 1h 30min 15s to s", "10,830 s")
        expectError("5w * 3h + 30min", "Cannot add Energy and Time.")
        expectNil("5w * 3h 30")
        expectDisplay("10n / 2m2 to pa", "5 Pa")
        expectDisplay("10m/s / 2s", "5 m/s²")
        expectDisplay("2kg * 3m/s²", "6 N")
        expectDisplay("1 / 20ms to hz", "50 Hz")
        expectDisplay("(1hr + 30min) to timespan", "1 hr 30 min")
        expectDisplay("100km / 40km/h to duration", "2 hr 30 min")
        expectNil("1m / 0s")
        expectDisplay("(2m)^0.5", "1.414213562 m^0.5")
        expectDisplay("sqrt(4kg)", "2 kg^0.5")
        expectNil("1kg!")
        expectDisplay("10kg +", "10 kg")
        expectCopy("10kg +", "10 kg")
        expectExpression("10kg +", "10 kg +")
        expectBadges("10kg +", source: "Expression", target: "Kilograms")
        expectNil("10kg + nonsense")
        expectNil("10unknown + 5unknown")
        expectNil("10kg / 0")
        expectDisplay("1234kg + 1kg", "1,235 kg")
        expectCopy("1234kg + 1kg", "1235 kg")

        // Date/time — evaluated against a fixed clock: Fri 2026-07-24 00:18 UTC
        expectDisplayAt("hrs till 9am", "8.7 hours")
        expectBadgesAt("hrs till 9am", source: "12:18 AM", target: "9:00 AM")
        expectDisplayAt("hrs till july", "8,207.7 hours")
        expectBadgesAt("hrs till july", source: "12:18 AM", target: "12:00 AM")
        expectDisplayAt("days till 9april", "259 days")
        expectBadgesAt(
            "days till 9april", source: "Friday, 24 July", target: "Friday, 9 April, 2027")
        expectDisplayAt("days till july", "342 days")
        expectBadgesAt(
            "days till july", source: "Friday, 24 July", target: "Thursday, 1 July, 2027")
        expectDisplayAt("days until tomorrow", "1 day")
        expectDisplayAt("weeks till 9april", "37 weeks")  // 259 / 7
        expectDisplayAt("today + 3 weeks", "14 August")
        expectDisplayAt("now + 90 min", "24 July at 1:48 AM")
        expectDisplayAt("jul 4 - today", "345 days")
        expectBadgesAt("jul 4 - today", source: "Sunday, 4 July, 2027", target: "Friday, 24 July")
        // Arithmetic with spaced operators must still be plain math, not date math
        expectDisplayAt("10 - 3", "7")
        expectDisplayAt("450 + 20%", "540")
        // Letter-free `m/d - m/d` is fraction math, not a date difference.
        expectDisplayAt("5/2 - 1/2", "2")
        expectDisplayAt("3/4 - 1/4", "0.5")
        expectDisplayAt("1/2 - 1/4", "0.25")
        // A slash date still reads as a date when the other side names a keyword
        expectDisplayAt("9/4 - today", "42 days")
        expectDisplayAt("today - 9/4", "-42 days")
        // Bare date/unit words alone are app searches, not cards
        expectNilAt("today")
        expectNilAt("july")
        expectNilAt("tomorrow")

        // Angle units (deg is a real unit now, not just a trig postfix)
        expectDisplay("1 deg", "0.01745329252 rad")
        expectExpression("1 deg", "1 deg")
        expectBadges("1 deg", source: "Degrees", target: "Radians")
        expectDisplay("90 deg to rad", "1.570796327 rad")
        expectDisplay("1 rad to deg", "57.29577951 deg")
        expectDisplay("1 turn to deg", "360 deg")
        expectDisplay("200 grad to deg", "180 deg")

        // Implied quantity of 1 for number-less conversions
        expectDisplay("day to s", "86,400 s")
        expectDisplay("deg to rad", "0.01745329252 rad")
        expectDisplay("m to ft", "3.280839895 ft")

        // `unit unit` shorthand → 1 of the first in the second
        expectDisplay("day s", "86,400 s")
        expectBadges("day s", source: "Days", target: "Seconds")
        expectDisplay("days s", "86,400 s")
        expectDisplay("hr min", "60 min")
        expectNil("m s")  // different categories → no card, no error

        // Extra unit categories: speed / pressure / data rate
        expectDisplay("100 kmh to mph", "62.13711922 mph")
        expectDisplay("60 mph to kmh", "96.56064 km/h")
        expectDisplay("100 mbps to kbps", "100,000 Kbps")
        expectBadges("100 kmh to mph", source: "Kilometers per Hour", target: "Miles per Hour")

        // Bare-unit auto-conversion gaps: same category, same treatment.
        expectDisplay("5 mbar", "0.07251886887 psi")
        expectDisplay("5 kPa", "0.7251886887 psi")
        expectDisplay("5 hPa", "0.07251886887 psi")
        expectDisplay("5 mmHg", "0.0966838873 psi")
        expectDisplay("5 Torr", "0.09668387352 psi")
        expectDisplay("100 bps", "0.1 Kbps")
        expectDisplay("1 Tbps", "1,000 Gbps")

        // Base conversion accepts an expression on the value side, as unit conversion does.
        expectDisplay("2*128 to hex", "0x100")
        expectDisplay("10*5 to hex", "0x32")

        // Percentage phrasings
        expectDisplay("20% off 500", "400")
        expectDisplay("50 as % of 200", "25%")

        // Badges on paths that previously had none
        expectBadges("255 to hex", source: "Decimal", target: "Hexadecimal")
        expectBadges("0xff to decimal", source: "Hexadecimal", target: "Decimal")
        expectBadges("3*3", source: "Expression", target: "Result")
        expectBadges("20% off 500", source: "Expression", target: "Discounted")

        // days since — past elapsed, against the fixed clock (Fri 2026-07-24)
        expectDisplayAt("days since 9jul", "15 days")
        expectBadgesAt("days since 9jul", source: "Thursday, 9 July", target: "Friday, 24 July")
        expectDisplayAt("weeks since 3jul", "3 weeks")
        expectDisplayAt("days since yesterday", "1 day")
        // The answer's weekday is the badge, so the date itself does not repeat it.
        expectBadgesAt("today + 3 weeks", source: "Friday, 24 July", target: "Friday")

        // Currency — against the fixed `fx` table below (1 USD = 0.92 EUR = 0.79 GBP = 157 JPY)
        expectDisplay("1 euro to dollars", "1.09 USD")
        expectExpression("1 euro to dollars", "1 EUR")
        expectBadges("1 euro to dollars", source: "Euro", target: "US Dollar")
        expectDisplay("50 GBP in euros", "58.23 EUR")
        expectDisplay("100 dollars to yen", "15,700.00 JPY")
        expectDisplay("100 usd -> eur", "92.00 EUR")
        expectDisplay("2*50 usd to eur", "92.00 EUR")  // expression on the value side
        expectDisplay("eur to usd", "1.09 USD")  // implied amount of 1
        expectCopy("100 dollars to yen", "15700.00 JPY")
        // Currency signs, prefixed and suffixed
        expectDisplay("€20 to GBP", "17.17 GBP")
        expectDisplay("20€ to GBP", "17.17 GBP")
        expectDisplay("USD1K to EUR", "920.00 EUR")
        expectDisplay("1kUSD to EUR", "920.00 EUR")
        expectDisplay("£50 in dollars", "63.29 USD")
        expectDisplay("$100 to yen", "15,700.00 JPY")
        // Sub-cent cross-rates widen instead of collapsing to 0.00
        expectDisplay("1 jpy to usd", "0.006369 USD")
        // …and stay in plain notation past 1e-5, where "%g" would flip to "5.539e-05"
        expectDisplay("1 idr to usd", "0.00005539 USD")
        expectCopy("1 idr to usd", "0.00005539 USD")
        // Currency never steals a query the unit table can answer
        expectDisplay("10 pounds to kilograms", "4.5359237 kg")
        expectDisplay("10 pounds", "4.5359237 kg")
        expectDisplay("10 pounds to euros", "11.65 EUR")
        expectBadges("10 pounds to euros", source: "British Pound", target: "Euro")
        // Currency ↔ unit is a friendly category error, like Weight ↔ Time
        expectError("10 usd to kg", "Cannot convert Currency to Weight.")
        expectError("10 kg to usd", "Cannot convert Weight to Currency.")
        // A known currency the snapshot doesn't quote, and no snapshot at all
        expectError("5 usd to npr", "No exchange rate for NPR.")
        expectErrorWithoutRates(
            "1 eur to usd", "Exchange rates unavailable — check your connection.")
        expectNil("10 usd to nonsense")
        expectNil("usd")  // a lone code is still an app search
        expectNil("btc")  // …and a lone ticker no more than a lone code
        // The table is generated from the feed, so "no rate" is what proves recognition.
        expectError("5 usd to zmw", "No exchange rate for ZMW.")
        expectError("5 usd to afn", "No exchange rate for AFN.")
        check(
            "CurrencyData sizes", expected: "true",
            got:
                "\(CurrencyData.all.count >= 150 && CurrencyData.signs.count >= 20 && CurrencyData.aliases.count >= 100)"
        )
        // Retired codes are filtered out, so a currency nobody spends can't shadow a live one
        expectNil("1 hrk to usd")
        expectNil("1 kuna to usd")
        // Badges come from CLDR's label, which is shorter than the registry name where it matters
        expectBadges("1 chf to usd", source: "Swiss Franc", target: "US Dollar")
        expectBadges("1 aed to usd", source: "UAE Dirham", target: "US Dollar")
        // Nouns only one currency claims are generated — nobody hand-typed these
        expectError("1 zloty to usd", "No exchange rate for PLN.")
        expectError("1 forint to usd", "No exchange rate for HUF.")
        expectError("1 taka to usd", "No exchange rate for BDT.")
        expectError("1 rand to usd", "No exchange rate for ZAR.")
        // Accented nouns resolve with or without the accent
        expectError("1 krónur to usd", "No exchange rate for ISK.")
        expectError("1 kronur to usd", "No exchange rate for ISK.")
        // Nouns several currencies share are the hand-written part, and they must still win
        expectDisplay("1 franc to usd", "1.23 USD")
        expectError("1 peso to usd", "No exchange rate for MXN.")
        // `krona` is contested (SEK vs ISK) and deliberately assigned to neither
        expectNil("1 krona to usd")
        // ISO 4217's own name for CNY is "Yuan Renminbi"; CLDR carries only "Chinese Yuan"
        expectError("1 rmb to usd", "No exchange rate for CNY.")
        expectError("1 renminbi to usd", "No exchange rate for CNY.")
        // CLDR signs TWD "NT$", so `ntd` is what Taiwan types; `twd` keeps working
        expectError("1 ntd to usd", "No exchange rate for TWD.")
        expectError("1299 usd to ntd", "No exchange rate for TWD.")
        // Slang is no longer carried: CLDR has no "quid", and we don't hand-maintain synonyms
        expectNil("50 quid to usd")
        expectNil("100 bucks to eur")
        // The last word of a name isn't always its noun — Special Drawing Rights.
        expectNil("1 rights to usd")
        // A result too small to show at all reads as a clean zero, never "-0.00"
        expectDisplay("-0.0000000000001 usd to eur", "0.00 EUR")
        expectDisplay("0 usd to eur", "0.00 EUR")
        expectDisplay("-5 usd to eur", "-4.60 EUR")
        // CUP (Cuban peso) is a generated code that collides with a unit; volume still wins
        expectDisplay("1 cup to ml", "236.5882365 mL")

        // Currency expressions — still pure and deterministic against the injected rate table
        expectDisplay("10$", "10.00 USD")
        expectExpression("10$", "10 USD")
        expectBadges("10$", source: "Expression", target: "US Dollar")
        expectDisplay("$10 + $5", "15.00 USD")
        expectDisplay("10$ + 5$", "15.00 USD")
        expectDisplay("$10 + €5", "14.20 EUR")
        expectDisplay("€5 + $10", "15.43 USD")
        // Sign-first money echoes amount-first, like every other quantity
        expectExpression("$10 + €5", "10 USD + 5 EUR")
        expectExpression("10$ + 5€", "10 USD + 5 EUR")
        expectDisplay("$10 * 2", "20.00 USD")
        expectDisplay("$10 / 4", "2.50 USD")
        expectDisplay("$10 / $2", "5")
        expectDisplay("$100 * 3%", "3.00 USD")
        expectDisplay("3% * $100", "3.00 USD")
        expectDisplay("$100 / 25%", "400.00 USD")
        expectDisplay("($100 * 3%) to eur", "2.76 EUR")
        expectDisplay("($10 + $5) to eur", "13.80 EUR")
        // A parenthesized conversion is a quantity, so it can be multiplied or added.
        expectDisplay("(20 eur to usd) * 30", "652.17 USD")
        expectDisplay("(20 eur to usd) * 20", "434.78 USD")
        expectDisplay("(20 sgd to usd) * 30", "444.44 USD")
        expectDisplay("2 * (20 eur to usd)", "43.48 USD")
        expectDisplay("(20 eur to usd) / 2", "10.87 USD")
        expectDisplay("(eur to usd) * 2", "2.17 USD")  // implied amount of 1
        expectDisplay("(20 eur to usd) + (10 gbp to usd)", "34.40 USD")
        expectDisplay("((20 eur to usd) + 1) * 2", "45.48 USD")
        expectDisplay("(10km to mi) * 2", "12.42742384 mi")
        expectDisplay("(1hr + 30min to s) * 2", "10,800 s")
        expectExpression("(20 eur to usd) * 30", "(20 EUR to USD) × 30")
        expectBadges("(20 eur to usd) * 30", source: "Expression", target: "US Dollar")
        expectDisplay("(20 eur to usd) *", "21.74 USD")
        expectError("(10 kg to usd) * 2", "Cannot convert Weight to Currency.")
        // A trailing suffix reports through the same conversion the group uses.
        expectError("($10 + $5) to npr", "No exchange rate for NPR.")
        expectError("(1kg + 500g) to usd", "Cannot convert Weight to Currency.")
        // A mid-expression `to` converts before it adds; `* 30` stays ambiguous, so it needs parens
        expectNil("20 eur to usd * 30")
        expectNil("20 eur to usd / 2")
        expectDisplay("20 eur to usd + 5 usd", "26.74 USD")
        expectDisplay("$10 +", "10.00 USD")
        expectBadges("$10 +", source: "Expression", target: "US Dollar")
        // Juxtaposition multiplies on either side of the amount, same as an explicit "*"
        expectDisplay("$5(2)", "10.00 USD")
        expectDisplay("5(2)$", "10.00 USD")
        expectDisplay("$5(2) to eur", "9.20 EUR")
        expectError("$10 + 5kg", "Cannot add Currency and Weight.")
        expectErrorWithoutRates(
            "$10 + $5", "Exchange rates unavailable — check your connection.")
        expectErrorWithoutRates(
            "$100 * 3%", "Exchange rates unavailable — check your connection.")
        expectErrorWithoutRates(
            "10$", "Exchange rates unavailable — check your connection.")

        // Crypto — priced by the same table, so a coin converts against fiat with no special case
        expectDisplay("1 btc to usd", "60,000.00 USD")
        expectDisplay("1 bitcoin to usd", "60,000.00 USD")
        expectDisplay("0.5 sol to eur", "46.00 EUR")
        expectDisplay("2 eth to gbp", "3,160.00 GBP")
        expectBadges("1 eth to usd", source: "Ethereum", target: "US Dollar")
        // Sub-cent widening covers a coin the same way it covers IDR
        expectDisplay("1 usd to btc", "0.00001667 BTC")
        expectCopy("1 usd to btc", "0.00001667 BTC")
        // A symbol the feed omits behaves exactly like an unquoted fiat code
        expectError("1 shib to usd", "No exchange rate for SHIB.")
        // Tickers are recognized rather than swallowed by the unit table
        expectError("1 dash to usd", "No exchange rate for DASH.")
        expectError("1 neo to usd", "No exchange rate for NEO.")
        // A ticker outranks a generated noun, and only that noun: `soles` still reaches PEN
        expectBadges("1 sol to usd", source: "Solana", target: "US Dollar")
        expectError("1 soles to usd", "No exchange rate for PEN.")
        check(
            "crypto is absent from the generated fiat table", expected: "true",
            got: "\(CurrencyData.all.allSatisfy { !CalcCurrency.cryptoCodes.contains($0.code) })")

        // A bare amount answers in the Mac's region currency, which is injected, never read
        expectDisplay("1 usd", "83.50 INR", region: "INR")
        expectExpression("1 usd", "1 USD", region: "INR")
        expectBadges("1 usd", source: "US Dollar", target: "Indian Rupee", region: "INR")
        expectDisplay("10$", "835.00 INR", region: "INR")
        expectDisplay("1 btc", "5,010,000.00 INR", region: "INR")
        expectCopy("1 usd", "83.50 INR", region: "INR")
        // The region names the currency written, so the dollar pairs with the euro instead
        expectDisplay("1 usd", "0.92 EUR", region: "USD")
        expectBadges("1 usd", source: "US Dollar", target: "Euro", region: "USD")
        expectDisplay("1 eur", "1.09 USD", region: "EUR")
        expectBadges("1 eur", source: "Euro", target: "US Dollar", region: "EUR")
        // Nothing to say: the region names one nobody quotes, or none at all
        expectDisplay("1 usd", "1.00 USD", region: "NPR")
        expectDisplay("1 usd", "1.00 USD", region: "ZZZ")
        expectDisplay("1 usd", "1.00 USD")
        // An operator, a target or a half-typed expression all keep the currency written
        expectDisplay("$10 + €5", "14.20 EUR", region: "INR")
        expectDisplay("$10 +", "10.00 USD", region: "INR")
        expectBadges("$10 +", source: "Expression", target: "US Dollar", region: "INR")
        expectDisplay("1 usd to eur", "0.92 EUR", region: "INR")
        expectDisplay("10 pounds", "4.5359237 kg", region: "INR")
        expectNil("usd", region: "INR")
        expectNil("btc", region: "INR")

        // The feed decoding, exercised the way the store hands it over
        expectSnapshot(
            "fiat only", fiat: fiatJSON, crypto: nil,
            expected: "USD=1 EUR=0.9 BTC=nil complete=false")
        expectSnapshot(
            "both feeds", fiat: fiatJSON, crypto: cryptoJSON,
            expected: "USD=1 EUR=0.9 BTC=5e-05 complete=true")
        // A coin payload quoted against another base is ignored rather than folded in wrongly
        expectSnapshot(
            "mismatched base", fiat: fiatJSON,
            crypto: Data(#"{"success":true,"target":"EUR","rates":{"BTC":20000}}"#.utf8),
            expected: "USD=1 EUR=0.9 BTC=nil complete=false")
        expectSnapshotThrows("no quotes", fiat: Data(#"{"success":true,"source":"USD","quotes":{}}"#.utf8))
        // A cached snapshot that prices no coin predates them, whatever its `fetchedAt` claims
        let coinless = CurrencyRates(base: "USD", rates: ["EUR": 0.9], fetchedAt: clock.now)
        check(
            "a coin-less snapshot is rejected on load", expected: "false",
            got: "\(CurrencyFeed.pricesCoins(coinless))")
        check("the fixture prices coins", expected: "true", got: "\(CurrencyFeed.pricesCoins(fx))")
        expectSnapshotThrows(
            "feed reported failure",
            fiat: Data(#"{"success":false,"source":"USD","quotes":{"USDEUR":0.9}}"#.utf8))

        // Slashed rate spellings — the tokenizer keeps a known `unit/unit` whole
        expectDisplay("100 km/h to mph", "62.13711922 mph")
        expectDisplay("60 mph in km/h", "96.56064 km/h")
        expectDisplay("5 m/s to km/h", "18 km/h")
        expectDisplay("100 km/h", "62.13711922 mph")
        expectExpression("100 km/h to mph", "100 km/h")
        expectBadges("5 m/s to km/h", source: "Meters per Second", target: "Kilometers per Hour")
        expectDisplay("100 mbit/s to mbps", "100 Mbps")
        // An unknown pairing leaves the slash as division, so ordinary arithmetic is untouched
        expectDisplay("10/2", "5")
        expectDisplay("6/2(1+2)", "9")
        expectDisplay("10 m / 2", "5 m")
        expectNil("1 km/x")

        // Workdays are 8 hours; weekends and holidays are a calendar's business, not a unit's
        expectDisplay("55h in workdays", "6.875 workdays")
        expectDisplay("3 workdays in hours", "24 hr")
        expectDisplay("2 businessdays to hours", "16 hr")
        expectBadges("55h in workdays", source: "Hours", target: "Workdays")

        // The rest of the trig set, plus the constants that come with it
        expectDisplay("cot(1)", "0.6420926159")
        expectDisplay("sec(1)", "1.850815718")
        expectDisplay("csc(1)", "1.188395106")
        expectDisplay("asin(1)", "1.570796327")
        expectDisplay("acos(1)", "0")
        expectDisplay("arctan(1)", "0.7853981634")
        expectDisplay("sinh(1)", "1.175201194")
        expectDisplay("tanh(0)", "0")
        expectDisplay("cbrt(27)", "3")
        expectDisplay("log2(1024)", "10")
        expectDisplay("exp(0)", "1")
        expectDisplay("sign(-5)", "-1")
        expectDisplay("trunc(3.7)", "3")
        expectDisplay("2 tau", "12.56637061")
        expectDisplay("phi * 2", "3.236067977")
        // `sec` is also seconds, and a unit position still wins
        expectDisplay("10 sec to min", "0.1666666667 min")
        expectDisplay("30 sec + 1 min", "1.5 min")

        // Percentage and ratio phrasings
        expectDisplay("15% tip on 42", "6.3")
        expectDisplay("20% tip of 80", "16")
        expectDisplay("50 is what % of 200", "25%")
        expectDisplay("30 is 20% of what", "150")
        expectDisplay("ratio of 3 to 5", "3 : 5")
        expectDisplay("ratio of 4 to 6", "2 : 3")
        expectDisplay("ratio of 1920 to 1080", "16 : 9")
        expectBadges("15% tip on 42", source: "Expression", target: "Tip")

        // List aggregates and snapping, both of which need the comma token
        expectDisplay("average of 10, 20, 30", "20")
        expectDisplay("avg of 1 and 2 and 3", "2")
        expectDisplay("sum of 10, 20, 30", "60")
        expectDisplay("max of 4, 9, 2", "9")
        expectDisplay("min of 4, 9, 2", "2")
        expectDisplay("sum of 2*3, 4", "10")
        expectDisplay("round 47 to nearest 5", "45")
        expectDisplay("round 12.3 to nearest 0.5", "12.5")
        // A comma between digits is still a grouping separator, and one operand is not a list
        expectDisplay("1,000 + 234", "1,234")
        expectNil("average of 5")
        expectNil("10,5")

        // Timespans break a duration into the units that fit it
        expectDisplay("145 mins to timespan", "2 hr 25 min")
        expectDisplay("8700 s to timespan", "2 hr 25 min")
        expectDisplay("90000 s to timespan", "1 day 1 hr")
        expectDisplay("55 h to timespan", "2 day 7 hr")
        expectDisplay("1000000 s to timespan", "1 wk 4 day 13 hr 46 min 40 s")
        expectBadges("145 mins to timespan", source: "Minutes", target: "Timespan")
        expectNil("10 km to timespan")

        expectDisplayAt("1970-01-01T00:00:00Z to unix", "0")
        expectDisplayAt("1970-01-01T01:00:00+01:00 to unix", "0")
        expectDisplayAt("1970-01-01T00:00:00.125Z to unix ms", "125")
        expectDisplayAt("1970-01-01T00:00:00.002Z to unix ms", "2")
        expectDisplayAt("1969-12-31T23:59:59.999Z to unix ms", "-1")
        expectDisplayAt("unix 1234567890.125 to unix ms", "1,234,567,890,125")
        expectDisplayAt("1970-01-01T00:00:00Z + 1h to unix", "3,600")
        expectDisplayAt("unix 0 to date", "1 January, 1970 at 12:00 AM")
        expectDisplayAt("1970-01-01T00:00:00Z to date", "1 January, 1970 at 12:00 AM")
        expectDisplayAt("1000 unix ms", "1 January, 1970 at 12:00:01 AM")
        expectDisplayAt("unix -1", "31 December, 1969 at 11:59:59 PM")
        expectDisplayAt("2026-07-24T07:30:00+02:00 + 30min", "24 July at 6:00 AM")
        expectNilAt("2026-02-30T00:00:00Z")
        expectNilAt("2026-07-24T00:00:00Z junk")
        expectNilAt("unix 1e30")

        // Time zones. The clock is UTC-pinned, so every one of these is exact.
        expectDisplayAt("time in tokyo", "9:18 AM")
        expectDisplayAt("time in sf", "5:18 PM (yesterday)")
        expectDisplayAt("what time is it in london", "1:18 AM")
        expectDisplayAt("time in kolkata", "5:48 AM")
        expectDisplayAt("time in utc", "12:18 AM")
        expectBadgesAt("time in tokyo", source: "UTC", target: "Tokyo")
        expectBadgesAt("time in sf", source: "UTC", target: "Los Angeles")
        // A named source zone overrides the Mac's own, so neither side has to be local
        expectDisplayAt("5pm london in sf", "9:00 AM")
        expectDisplayAt("9:30am in nyc", "5:30 AM")
        expectDisplayAt("5pm in tokyo", "2:00 AM (tomorrow)")
        expectBadgesAt("5pm london in sf", source: "London", target: "Los Angeles")
        // Aliases cover what the identifiers don't spell, and DST is Foundation's own answer
        expectDisplayAt("time in nyc", "8:18 PM (yesterday)")
        expectDisplayAt("time in cet", "2:18 AM")
        // A zone name never outranks a unit or a currency, and a non-zone stays a search
        expectDisplay("1 cup to ml", "236.5882365 mL")
        expectNil("time in xyzzy")
        expectNil("in tokyo")
        expectNil("time")

        // IATA airport codes, which Foundation has no notion of
        expectDisplayAt("time in vie", "2:18 AM")
        expectDisplayAt("time in lhr", "1:18 AM")
        expectDisplayAt("time in nrt", "9:18 AM")
        expectDisplayAt("time in sfo", "5:18 PM (yesterday)")
        expectBadgesAt("time in vie", source: "UTC", target: "Vienna")
        expectDisplayAt("5pm vie in nrt", "12:00 AM (tomorrow)")
        // `mad` stays the Moroccan dirham, and `ist` stays India Standard Time
        expectError("10 mad to usd", "No exchange rate for MAD.")
        expectBadgesAt("time in ist", source: "UTC", target: "Kolkata")

        // A trailing offset shifts a zone answer, so the whole thing stays one query
        expectDisplayAt("5pm london in sf", "9:00 AM")
        expectDisplayAt("5pm london in sf + 2h", "11:00 AM")
        expectDisplayAt("5pm london in sf - 1 hour", "8:00 AM")
        expectDisplayAt("5pm london in sf + 30 min", "9:30 AM")
        expectBadgesAt("5pm london in sf + 2h", source: "London", target: "Los Angeles")
        // A unit conversion is not a zone offset, and neither is a bare sum
        expectDisplay("1 cup to ml", "236.5882365 mL")
        expectNil("5pm london in sf + 2 kg")

        // `<weekday> in <n> weeks` answers that weekday inside the week it lands in
        expectDisplayAt("monday in 3 weeks", "10 August")
        expectDisplayAt("monday in 1 week", "27 July")
        expectDisplayAt("tuesday in 2 weeks", "4 August")
        expectDisplayAt("friday in 2 weeks", "7 August")
        expectBadgesAt("monday in 3 weeks", source: "Friday, 24 July", target: "Monday")
        // A month is not a weekday, and `in` still reaches the unit path
        expectNil("monday in 3 kg")
        expectDisplay("10 in in cm", "25.4 cm")

        // A zone's offset from the Mac's own
        expectDisplayAt("diff paris", "2:18 AM (+2h)")
        expectDisplayAt("time diff tokyo", "9:18 AM (+9h)")
        expectDisplayAt("diff kolkata", "5:48 AM (+5h 30m)")
        expectBadgesAt("diff paris", source: "UTC", target: "Paris")
        expectNil("diff xyzzy")

        // A duration where a zone would go, and both at once
        expectDisplayAt("time in 4 hours", "4:18 AM")
        expectDisplayAt("time in 90 min", "1:48 AM")
        expectDisplayAt("time in 4 hours in san francisco", "9:18 PM (yesterday)")

        // A bare offset on a clock answer is hours, the unit the answer already implies
        expectDisplayAt("time in tokyo + 2", "11:18 AM")
        expectDisplayAt("time in tokyo - 2", "7:18 AM (tomorrow)")
        expectDisplayAt("5pm london in sf + 3", "12:00 PM")
        // Only the offset implies it: a bare number is still no zone, and plain math is untouched
        expectNilAt("time in 4")
        expectDisplay("5 + 3", "8")

        // Dotted dates are day-first, the convention that writes them
        expectDisplayAt("19.2.27 + 3", "22 February, 2027")
        expectDisplayAt("19.02.2027 + 3", "22 February, 2027")
        expectDisplayAt("19.2.27 - 3", "16 February, 2027")
        expectDisplayAt("31.12.26 + 1", "1 January, 2027")
        expectDisplayAt("19.2.27 + 3 weeks", "12 March, 2027")
        expectBadgesAt("19.2.27 + 3", source: "Friday, 19 February, 2027", target: "Monday")
        // A decimal is not a date, and a version number is not one either
        expectDisplay("1.5 + 3", "4.5")
        expectDisplay("99.99 + 0.01", "100")
        expectNilAt("1.2.3 + 1")
        expectNilAt("1.5.5 + 3")
        // An impossible day still earns no card
        expectNilAt("30.2.27 + 1")

        // Malformed input a fuzzer found: both of these read past the end of the token array
        expectNil("round is next round to")
        expectNilAt(": from to at sf")
        expectNil("round to")
        expectNil("round 5 to")
        expectNilAt(": at sf")
        expectNil("is what % of")
        expectNil("tip on")

        // The gate scans for whitespace, not a literal space, so a pasted NBSP still lands.
        expectDisplayAt("time\u{a0}in\u{a0}tokyo", "9:18 AM")
        expectDisplayAt("time\u{9}in\u{9}tokyo", "9:18 AM")
        expectDisplayAt("time\u{2009}in\u{2009}tokyo", "9:18 AM")

        // The ordinal dot German and Austrian dates write after the day
        expectDisplayAt("28. aug + 3", "31 August")
        expectDisplayAt("28. august + 3", "31 August")
        expectDisplayAt("28.aug + 3", "31 August")
        // Nearest, not next: from July, January is six months back rather than six ahead
        expectDisplayAt("1. jan + 1", "2 January")
        expectDisplayAt("28. aug 2027 + 3", "31 August, 2027")
        expectBadgesAt("28. aug + 3", source: "Friday, 28 August", target: "Monday")
        // Only a trailing dot is an ordinal, so a decimal day is still not a date
        expectNilAt("28.5 aug + 1")

        // A written day is its own reason for a card: the weekday is why you typed it
        expectDisplayAt("25. aug", "25 August")
        expectDisplayAt("25 aug", "25 August")
        expectDisplayAt("aug 25", "25 August")
        expectDisplayAt("25.8.27", "25 August, 2027")
        expectDisplayAt("1. jan", "1 January")
        expectBadgesAt("25. aug", source: "Friday, 24 July", target: "Tuesday")
        // A bare date takes the year it is nearest, so it agrees with the same date plus a shift
        expectDisplayAt("25. aug + 3", "28 August")
        // A month or a relative word alone is still an app search
        expectNilAt("july")
        expectNilAt("aug")
        expectNilAt("today")
        expectNilAt("tomorrow")

        // Date arithmetic chains left to right, however many terms it carries
        expectDisplayAt("17.2.26 + 100 week days - 4 + 2", "5 July")
        expectDisplayAt("17.2.26 + 100 weekdays", "7 July")
        expectDisplayAt("17.2.26 + 100 weekdays - 4", "3 July")
        expectDisplayAt("today + 3 weeks - 2 days", "12 August")
        expectDisplayAt("today + 5 + 2", "31 July")
        expectDisplayAt("today + 1 day + 1 day + 1 day", "27 July")
        expectDisplayAt("now + 90 min + 30 min", "24 July at 2:18 AM")
        expectDisplayAt("3:45pm + 5 - 2", "24 July at 6:45 PM")
        expectBadgesAt("17.2.26 + 100 week days - 4 + 2", source: "Tuesday, 17 February", target: "Sunday")
        // Every term must be a duration, so a unit or a stray word still earns no card
        expectNilAt("today + 3 weeks - kg")
        expectNilAt("today + 5 - abc")
        // Two moments are still a difference, and letter-free operands are still arithmetic
        expectDisplayAt("jul 4 - today", "345 days")
        expectDisplay("5 + 3 - 2", "6")
        expectDisplay("5/2 - 1/2", "2")

        // Accented spellings resolve, since the identifiers carry none
        expectDisplayAt("time in são paulo", "9:18 PM (yesterday)")
        expectDisplayAt("time in sao paulo", "9:18 PM (yesterday)")
        expectDisplayAt("time in zürich", "2:18 AM")

        // Cities IANA never names, because their clocks never differed from the zone's own
        expectBadgesAt("time in graz", source: "UTC", target: "Vienna")
        expectBadgesAt("time in salzburg", source: "UTC", target: "Vienna")
        expectBadgesAt("time in klagenfurt", source: "UTC", target: "Vienna")
        expectBadgesAt("time in hannover", source: "UTC", target: "Berlin")
        expectBadgesAt("time in stuttgart", source: "UTC", target: "Berlin")
        expectBadgesAt("time in basel", source: "UTC", target: "Zurich")
        expectBadgesAt("time in manchester", source: "UTC", target: "London")
        expectBadgesAt("time in florence", source: "UTC", target: "Rome")
        expectBadgesAt("time in lyon", source: "UTC", target: "Paris")
        expectBadgesAt("time in krakow", source: "UTC", target: "Warsaw")
        // Their accented spellings fold onto the same entry
        expectBadgesAt("time in düsseldorf", source: "UTC", target: "Berlin")
        expectBadgesAt("time in kraków", source: "UTC", target: "Warsaw")
        expectBadgesAt("time in malmö", source: "UTC", target: "Stockholm")
        expectBadgesAt("5pm graz in basel", source: "Vienna", target: "Zurich")

        // A bare number takes the unit its moment implies
        expectDisplayAt("3:45pm + 5", "24 July at 8:45 PM")
        expectDisplayAt("3:45pm - 2", "24 July at 1:45 PM")
        expectDisplayAt("august 5 + 5", "10 August")
        expectDisplayAt("august 5 - 5", "31 July")

        // A named moment earns a card once it carries a time or a qualifier
        expectDisplayAt("tomorrow at 9am", "25 July at 9:00 AM")
        expectDisplayAt("next monday", "27 July")
        expectDisplayAt("last friday", "17 July")
        expectBadgesAt("tomorrow at 9am", source: "Friday, 24 July", target: "Saturday")
        expectDisplayAt("next monday at 7:30 + 5", "27 July at 12:30 PM")
        expectDisplayAt("next monday at 7:30 + 1 day 2h 15min - 1", "28 July at 8:45 AM")
        expectDisplayAt("tomorrow at 23:30 + 1.5 hours", "26 July at 1:00 AM")
        expectDisplayAt("3 days from next monday at 7:30", "30 July at 7:30 AM")
        expectDisplayAt("1h 30min ago", "23 July at 10:48 PM")
        expectDisplayAt("31.1.26 at 7:30 + 1 month", "28 February at 7:30 AM")
        expectDisplayAt("29.2.24 + 1 year", "28 February, 2025")
        expectDisplayAt("today + 1 year 2 months - 1 day", "23 September, 2027")
        expectDisplayAt("1. jan + 1 + 1", "3 January")
        expectDisplayAt("hours till tomorrow at 7:30", "31.2 hours")
        expectDisplayAt("hours since yesterday at noon", "12.3 hours")
        expectDisplayAt("hours till friday at midnight", "167.7 hours")
        expectDisplayAt("hours since friday at midnight", "0.3 hours")
        expectDisplayAt("hours till jul 24 at midnight", "8,759.7 hours")
        expectDisplayAt("next monday at 9:30 - next monday at 7:00", "2 hr 30 min")
        expectDisplayAt("next monday at 9:30 - next monday at 7:00 to minutes", "150 min")
        expectDisplayAt("2026-08-01 - 2026-07-24", "8 days")
        expectDisplayAt("today at 9:30 - today at 7:00 to hours", "2.5 hr")
        expectDisplayAt("now + 5 seconds", "24 July at 12:18:05 AM")
        expectDisplayAt("next\u{a0}monday at\t7:30 + 5", "27 July at 12:30 PM")
        expectDisplayAt("tomorrow - 5 weekdays", "20 July")
        expectDisplayAt("today + 10000 weekdays", "21 November, 2064")
        for query in [
            "tomorrow at 7:99", "tomorrow at 7::30", "today + 1.5 months",
            "today + 1h 30", "today + -9223372036854775808 weekdays", "today + 9223372036854775807 weeks"
        ] {
            expectNilAt(query)
        }
        var vienna = clock.calendar
        vienna.timeZone = TimeZone(identifier: "Europe/Vienna")!
        expectDisplayAt("2026-03-28 at 7:30 + 1 day", "29 March at 7:30 AM", calendar: vienna)
        expectDisplayAt("2026-03-28 at 7:30 + 24 hours", "29 March at 8:30 AM", calendar: vienna)
        expectDisplayAt("2026-03-29 at 7:30 - 2026-03-28 at 7:30 to hours", "23 hr", calendar: vienna)
        expectDisplayAt("2026-10-24 at 7:30 + 1 day", "25 October at 7:30 AM", calendar: vienna)
        expectDisplayAt("2026-10-25 at 7:30 - 2026-10-24 at 7:30 to hours", "25 hr", calendar: vienna)
        expectDisplayAt("1:00 - 3:00", "-2 hr", calendar: vienna)
        let springNow = clock.calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        expectNilAt("2:30am vienna in london", now: springNow, calendar: vienna)
        // A lone date word is still an app search
        expectNilAt("tomorrow")
        expectNilAt("today")

        // Spoken function and operator names
        expectDisplay("square root of 625", "25")
        expectDisplay("square root of 64", "8")
        expectDisplay("cube root of 27", "3")
        expectDisplay("2 power 10", "1,024")
        expectDisplay("2 power 3 power 2", "512")

        // Business days skip weekends. The clock is Fri 2026-07-24, so every hop crosses one.
        expectDisplayAt("today + 1 business day", "27 July")
        expectDisplayAt("today + 5 business days", "31 July")
        expectDisplayAt("today - 1 business day", "23 July")
        expectDisplayAt("today - 3 business days", "21 July")
        expectDisplayAt("tomorrow + 10 work days", "7 August")
        expectDisplayAt("today + 15 workdays", "14 August")
        expectDisplayAt("today + 5 weekdays", "31 July")
        // Raycast's own shape: the weekday rides the badge rather than the date
        expectBadgesAt("today + 5 business days", source: "Friday, 24 July", target: "Friday")
        expectBadgesAt("today + 1 business day", source: "Friday, 24 July", target: "Monday")
        // The duration may lead, with `from` naming the anchor or `ago` implying today
        expectDisplayAt("5 weekdays from now", "31 July")
        expectDisplayAt("10 business days from today", "7 August")
        expectDisplayAt("3 days from today", "27 July")
        expectDisplayAt("2 weeks ago", "10 July")
        expectDisplayAt("3 days ago", "21 July")
        expectBadgesAt("5 weekdays from now", source: "Friday, 24 July", target: "Friday")
        // A month name with both a day and a year
        expectDisplayAt("august 26 2026 + 15 workdays", "16 September")
        expectDisplayAt("august 26 2026 + 15 days", "10 September")
        expectDisplayAt("26 august 2026 + 1 day", "27 August")
        expectDisplayAt("august 26 2027 + 1 day", "27 August, 2027")
        // The 8-hour unit is a different thing, and keeps answering as one
        expectDisplay("55h in workdays", "6.875 workdays")
        expectDisplay("3 workdays in hours", "24 hr")
        expectNil("5 from 10")

        // A conversion mid-expression, which used to need parentheses
        expectDisplay("10kg to lb + 3lb", "25.04622622 lb")
        expectDisplay("10kg to lb - 1lb", "21.04622622 lb")
        expectDisplay("100 km/h to mph + 3mph", "65.13711922 mph")
        expectDisplay("10km to mi + 3mi", "9.213711922 mi")
        expectDisplay("10kg to lb + 3lb + 1lb", "26.04622622 lb")
        expectDisplay("10km to mi + 3mi to km", "14.828032 km")
        expectDisplay("10kg to lb + 3", "25.04622622 lb")
        expectError("1kg to m + 3", "Cannot convert Weight to Length.")
        // A trailing `to` still converts the whole expression rather than the last operand
        expectDisplay("10kg + 500g to lb", "23.14853753 lb")
        expectDisplay("1kg + 1kg to g", "2,000 g")
        expectDisplay("2hr + 30min to min", "150 min")

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Fixed clock for deterministic date/time tests (Fri 2026-07-24 00:18:00 UTC)

    static let clock: (now: Date, calendar: Calendar) = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 24
        components.hour = 0
        components.minute = 18
        components.second = 0
        return (calendar.date(from: components)!, calendar)
    }()

    // MARK: - Fixed exchange rates so currency answers are deterministic

    /// Absent on purpose: a recognized code must reach "no exchange rate", not no card.
    static let fx = CurrencyRates(
        base: "USD",
        rates: [
            "USD": 1, "EUR": 0.92, "GBP": 0.79, "JPY": 157, "INR": 83.5, "CAD": 1.36,
            "KRW": 1330, "IDR": 18053, "CHF": 0.81, "AED": 3.6725, "SGD": 1.35,
            "BTC": 1.0 / 60_000, "ETH": 1.0 / 2_000, "SOL": 1.0 / 100, "DOGE": 10
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_785_000_000))

    /// A pair whose base isn't the source and a nonsense rate, both of which must be dropped.
    static let fiatJSON = Data(
        #"{"success":true,"source":"USD","quotes":{"USDEUR":0.9,"EURGBP":0.8,"USDBAD":-1}}"#.utf8)
    /// Quoted the other way round — 1 BTC costs 20,000 USD, so the table stores 0.00005.
    static let cryptoJSON = Data(#"{"success":true,"target":"USD","rates":{"BTC":20000}}"#.utf8)

    // MARK: - Helpers

    static func expectDisplayAt(_ query: String, _ expected: String, calendar: Calendar? = nil) {
        guard
            case .value(let display, _)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: calendar ?? clock.calendar)?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: display)
    }

    static func expectBadgesAt(_ query: String, source: String, target: String) {
        guard let result = CalcEngine.evaluate(query, now: clock.now, calendar: clock.calendar)
        else {
            fail(query, expected: "\(source) → \(target)", got: "nil")
            return
        }
        check(query + " [source badge]", expected: source, got: result.sourceBadge ?? "nil")
        check(query + " [target badge]", expected: target, got: result.targetBadge ?? "nil")
    }

    static func expectNilAt(_ query: String, now: Date = clock.now, calendar: Calendar? = nil) {
        if let result = CalcEngine.evaluate(query, now: now, calendar: calendar ?? clock.calendar) {
            fail(query, expected: "nil", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    /// The region currency is injected, so the suite ignores the host's region.
    static func label(_ query: String, _ region: String?) -> String {
        region.map { "\(query) [region \($0)]" } ?? query
    }

    static func expectBadges(
        _ query: String, source: String, target: String, region: String? = nil
    ) {
        guard
            let result = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)
        else {
            fail(label(query, region), expected: "\(source) → \(target)", got: "nil")
            return
        }
        check(
            label(query, region) + " [source badge]", expected: source,
            got: result.sourceBadge ?? "nil")
        check(
            label(query, region) + " [target badge]", expected: target,
            got: result.targetBadge ?? "nil")
    }

    static func expectDisplay(_ query: String, _ expected: String, region: String? = nil) {
        guard
            case .value(let display, _)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)?.payload
        else {
            fail(label(query, region), expected: expected, got: "nil / error")
            return
        }
        check(label(query, region), expected: expected, got: display)
    }

    static func expectCopy(_ query: String, _ expected: String, region: String? = nil) {
        guard
            case .value(_, let copy)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)?.payload
        else {
            fail(label(query, region), expected: expected, got: "nil / error")
            return
        }
        check(label(query, region), expected: expected, got: copy)
    }

    static func expectError(_ query: String, _ expected: String) {
        guard
            case .error(let message)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx)?.payload
        else {
            fail(query, expected: "error: \(expected)", got: "nil / value")
            return
        }
        check(query, expected: expected, got: message)
    }

    /// No snapshot has landed yet — first run, or still offline.
    static func expectErrorWithoutRates(_ query: String, _ expected: String) {
        guard
            case .error(let message)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: nil)?.payload
        else {
            fail(query, expected: "error: \(expected)", got: "nil / value")
            return
        }
        check(query, expected: expected, got: message)
    }

    static func expectExpression(_ query: String, _ expected: String, region: String? = nil) {
        guard
            let result = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)
        else {
            fail(label(query, region), expected: expected, got: "nil")
            return
        }
        check(label(query, region), expected: expected, got: result.expression)
    }

    /// `CurrencyFeed` is handed the two payloads exactly as the store receives them.
    static func expectSnapshot(_ name: String, fiat: Data, crypto: Data?, expected: String) {
        guard let result = try? CurrencyFeed.snapshot(fiat: fiat, crypto: crypto, now: clock.now)
        else {
            fail(name, expected: expected, got: "threw")
            return
        }
        let show = { (code: String) in result.rates.rates[code].map(CalcFormatter.copyText) ?? "nil" }
        check(
            name, expected: expected,
            got: "USD=\(show("USD")) EUR=\(show("EUR")) BTC=\(show("BTC")) "
                + "complete=\(result.complete)")
    }

    static func expectSnapshotThrows(_ name: String, fiat: Data) {
        if let result = try? CurrencyFeed.snapshot(fiat: fiat, crypto: nil, now: clock.now) {
            fail(name, expected: "throws", got: "\(result.rates.rates.count) rates")
        } else {
            passes += 1
        }
    }

    static func expectNil(_ query: String, region: String? = nil) {
        if let result = CalcEngine.evaluate(
            query, now: clock.now, calendar: clock.calendar, rates: fx, region: region)
        {
            fail(label(query, region), expected: "nil", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    static func check(_ query: String, expected: String, got: String) {
        if got == expected {
            passes += 1
        } else {
            fail(query, expected: expected, got: got)
        }
    }

    static func fail(_ query: String, expected: String, got: String) {
        failures += 1
        print("FAIL  \(query)\n      expected: \(expected)\n      got:      \(got)")
    }
}
