import Testing

@testable import Tinycast

extension CalcTests {
    @Test(arguments: [
        .display("10km to mi", "6.213711922 mi"),
        .display("10 km in miles", "6.213711922 mi"),
        .display("5ft in cm", "152.4 cm"),
        .display("1 m to ft", "3.280839895 ft"),
        .display("10 cm in in", "3.937007874 in"),
        .display("10 in in cm", "25.4 cm"),
        .display("16 oz to lb", "1 lb"),
        .display("2.2 lbs to kg", "0.997903214 kg"),
        .display("100 C to F", "212 °F"),
        .display("32F to C", "0 °C"),
        .display("273.15K to C", "0 °C"),
        .display("273.15 K to C", "0 °C"),
        .display("10 k to c", "-263.15 °C"),
        .display("0 F to C", "-17.77777778 °C"),
        .display("300 K to C", "26.85 °C"),
        .display("90min to hr", "1.5 hr"),
        .display("2hr to min", "120 min"),
        .display("1day to sec", "86,400 s"),
        .display("1 week to hr", "168 hr"),
        .display("3 months to days", "91.310625 day"),
        .display("3.5 years to days", "1,278.34875 day"),
        .copy("3.5 years to days", "1278.34875 day"),
        .display("1month in days", "30.436875 day"),
        .display("1mo -> s", "2,629,746 s"),
        .display("1YEAR to s", "31,556,952 s"),
        .display("1yr to months", "12 mo"),
        .display("12 months to years", "1 yr"),
        .display("365.2425 days to year", "1 yr"),
        .display("-0.5 years to months", "-6 mo"),
        .display("0 months to days", "0 day"),
        .display("(1 year + 6 months) to days", "547.86375 day"),
        .badges("3.5 years to days", source: "Years", target: "Days"),
        .display("2 acre to m2", "8,093.712845 m²"),
        .display("1 m² to ft²", "10.76391042 ft²"),
        .display("2L -> mL", "2,000 mL"),
        .display("1 cup to tbsp", "16 tbsp"),
        .display("1 gal to L", "3.785411784 L"),
        .display("1 GiB to MB", "1,073.741824 MB"),
        .display("1 GB to MiB", "953.6743164 MiB"),
        .display("8 bit to byte", "1 B"),
        .display("2*5 km to mi", "6.213711922 mi")
    ] as [Case])
    func unitsConvert(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .error("10kg to sec", "Cannot convert Weight to Time."),
        .error("100 mL to km", "Cannot convert Volume to Length."),
        .error("1 GB to hr", "Cannot convert Digital Storage to Time."),
        .error("1 year to kg", "Cannot convert Time to Weight.")
    ] as [Case])
    func convertingAcrossDimensionsIsAnError(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("1m", "3 feet 3.37007874 inches"),
        .expression("1m", "1 m"),
        .badges("1m", source: "Meters", target: "Feet"),
        .display("1hr", "60 min"),
        .badges("1hr", source: "Hours", target: "Minutes"),
        .display("3 weeks", "21 day"),
        .display("3 days", "72 hr"),
        .display("3 months", "91.310625 day"),
        .display("3.5 years", "1,278.34875 day"),
        .badges("3 months", source: "Months", target: "Days"),
        .badges("3.5 years", source: "Years", target: "Days"),
        .display("5ft", "1.524 m"),
        .display("100g", "3.527396195 oz"),
        .display("2*3 kg", "6 kg"),
        .display("20 celsius", "68 °F"),
        .display("50cm", "19.68503937 in"),
        .display("100 c", "212 °F"),
        .display("32f", "0 °C"),
        .display("10C", "50 °F"),
        .display("10ºC", "50 °F"),
        .display("50 ºf", "10 °C"),
        .noResult("5 k")
    ] as [Case])
    func aBareQuantityAnswersInItsCompanionUnit(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10kg + 5kg", "15 kg"),
        .copy("10kg + 5kg", "15 kg"),
        .expression("10kg + 5kg", "10 kg + 5 kg"),
        .expression("10kg * 3%", "10 kg × 3%"),
        .expression("(10kg + 5kg) * 3%", "(10 kg + 5 kg) × 3%"),
        .expression("-5kg + 2kg", "-5 kg + 2 kg"),
        .expression("5 feet 3 inches", "5 ft 3 in"),
        .expression("hypot(3m,400cm)", "hypot(3 m, 400 cm)"),
        .expression("min(1km,999m)", "min(1 km, 999 m)"),
        .expression("round(2.567km,1)", "round(2.567 km, 1)"),
        .expression("2*sqrt(9)m", "2 × sqrt(9) m"),
        .expression("cube root of -8m3", "cube root of -8 m³"),
        .expression("15% of -2kg", "15% of -2 kg"),
        .expression("10kg - 5kg", "10 kg - 5 kg"),
        .expression("2 * 5feet 3inches", "2 × 5 ft 3 in"),
        .badges("10kg + 5kg", source: "Expression", target: "Kilograms"),
        .display("10kg + 10g", "10,010 g"),
        .display("10kg + 500g", "10,500 g"),
        .display("500g + 1kg", "1.5 kg"),
        .copy("500g + 1kg", "1.5 kg"),
        .display("10lb + 5kg", "9.5359237 kg"),
        .display("1m + 50cm", "150 cm"),
        .display("2hr + 30min", "150 min"),
        .display("1GiB + 512MiB", "1,536 MiB"),
        .display("1L - 250mL", "750 mL"),
        .display("-5kg + 2kg", "-3 kg"),
        .display("-(2kg + 500g)", "-2,500 g"),
        .display("10 pounds + 5 pounds", "15 lb"),
        .display("1m² + 10ft²", "20.76391042 ft²"),
        .display("1L + 1cup", "5.226752838 cup"),
        .display("1GB + 1GiB", "1.931322575 GiB"),
        .display("90deg + 1rad", "2.570796327 rad"),
        .display("60mph + 10kmh", "106.56064 km/h"),
        .display("1bar + 10psi", "24.50377377 psi"),
        .display("1Gbps + 500Mbps", "1,500 Mbps")
    ] as [Case])
    func addingQuantitiesAnswersInTheLastUnitTyped(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10kg + 2 * 5kg", "20 kg"),
        .display("(10kg + 5kg) * 2", "30 kg"),
        .display("2 * (3kg + 500g)", "7,000 g"),
        .display("20kg / 2 + 3kg", "13 kg"),
        .display("20kg / (2 + 3)", "4 kg"),
        .display("5kg * 3", "15 kg"),
        .display("10kg / 4", "2.5 kg"),
        .display("5kg / 2kg", "2.5"),
        .badges("5kg / 2kg", source: "Expression", target: "Result"),
        .display("5kg / 500g", "10"),
        .display("1kg / 3", "0.3333333333 kg"),
        .display("10kg * (2 + 3)", "50 kg"),
        .display("10kg / (2 * 5)", "1 kg"),
        .display("(10kg * 3) / 5kg", "6"),
        .display("10kg / (5kg / 2)", "4"),
        .display("(2kg + 500g) * 4", "10,000 g"),
        .display("(20kg - 5kg) / 3", "5 kg")
    ] as [Case])
    func scalarArithmeticKeepsTheUnit(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10kg + 20%", "12 kg"),
        .display("10kg - 20%", "8 kg"),
        .display("10kg * 20%", "2 kg"),
        .display("10kg * 3%", "0.3 kg"),
        .display("3% * 10kg", "0.3 kg"),
        .display("10kg * 0%", "0 kg"),
        .display("10kg * -3%", "-0.3 kg"),
        .display("10kg / 25%", "40 kg"),
        .display("10kg / 200%", "5 kg"),
        .display("10kg * 3% + 1kg", "1.3 kg"),
        .display("(10kg + 5kg) * 3%", "0.45 kg"),
        .display("10kg * 3% to g", "300 g"),
        .copy("10kg * 3% to g", "300 g"),
        .display("20% of (10kg + 5kg)", "3 kg"),
        .display("3% of 10kg", "0.3 kg"),
        .noResult("10kg / 0%"),
        .display("19m + 47%", "27.93 m")
    ] as [Case])
    func aPercentScalesAQuantity(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .expression("10km to mi *", "10km to mi ×"),
        .display("10km to mi *", "6.213711922 mi"),
        .expression("255 to hex +", "255 to hex +"),
        .badges("0xff -", source: "Hexadecimal", target: "Decimal"),
        .display("0xff -", "255")
    ] as [Case])
    func aPartialAfterAConversionEchoesTheTypedText(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("(1kg + 500g) to lb", "3.306933933 lb"),
        .display("10kg + 500g to lb", "23.14853753 lb"),
        .display("(10lb + 5kg) to kg", "9.5359237 kg"),
        .display("(1m + 50cm) to ft", "4.921259843 ft"),
        .badges("(1kg + 500g) to lb", source: "Expression", target: "Pounds"),
        .error("(1kg + 500g) to m", "Cannot convert Weight to Length.")
    ] as [Case])
    func aConversionSuffixAppliesToTheWholeExpression(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("5 feet 3 inches to cm", "160.02 cm"),
        .display("5 feet 3 inches", "5.25 ft"),
        .display("1hr 30min", "1.5 hr"),
        .display("5feet + 1m", "2.524 m"),
        .badges("5feet + 1m", source: "Expression", target: "Meters"),
        .display("1kg + 500g + 2lb", "5.306933933 lb"),
        .display("2 * 5kg", "10 kg"),
        .display("3 * 2m", "6 m")
    ] as [Case])
    func aCompositeReadsAsOneQuantity(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("20 celsius + 10 celsius", "30 °C"),
        .display("68 fahrenheit - 32 fahrenheit", "36 °F"),
        .error("20 celsius + 50 fahrenheit", "Cannot combine temperatures with different units.")
    ] as [Case])
    func temperaturesOnlyCombineInOneUnit(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .error("1kg + 1m", "Cannot add Weight and Length."),
        .error("1kg + 1hr", "Cannot add Weight and Time."),
        .display("1kg + 1", "2 kg"),
        .display("10kg + 5", "15 kg"),
        .display("5kg+5", "10 kg"),
        .display("5 + 10kg", "15 kg"),
        .display("$10 + 5", "15.00 USD"),
        .badges("5kg+5", source: "Expression", target: "Kilograms"),
        .display("10kg + -20%", "9.8 kg")
    ] as [Case])
    func aBareNumberAgainstAQuantityTakesItsUnit(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .noResult("1hr 30"),
        .noResult("5 feet 3"),
        .display("1kg * 1m", "1 kg·m"),
        .display("1cm/m", "0.01"),
        .display("sqrt(4m) to cm^0.5", "20 cm^0.5"),
        .display("1 kg/m3 to g/cm3", "0.001 g/cm³"),
        .display("10m * 2s to cm*s", "2,000 cm·s"),
        .display("2kg / 4m3", "0.5 kg/m³"),
        .display("1kg/m3 + 1g/cm3", "1.001 g/cm³"),
        .display("100 USD / 4hr", "25 USD/hr"),
        .display("25 USD/hr * 8hr", "200.00 USD"),
        .display("8hr * 25 USD/hr", "200.00 USD"),
        .display("25 USD/hr to EUR/min", "0.3833333333 EUR/min")
    ] as [Case])
    func compoundUnitsMultiplyAndDivide(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("5 usd per gallon to eur per liter", "1.215191441 EUR/L"),
        .display("5 usd per gallon in eur per liter", "1.215191441 EUR/L"),
        .display("5 USD/gal to EUR/L", "1.215191441 EUR/L"),
        .display("60 miles per hour to km/h", "96.56064 km/h"),
        .display("50 usd per hour", "50 USD/hr"),
        .display("10 divided by 2", "5"),
        .display("10 plus 5", "15"),
        .display("10 minus 3", "7"),
        .display("6 times 7", "42"),
        .display("10 multiplied by 3", "30"),
        .noResult("pages per"),
        .noResult("world times 5")
    ] as [Case])
    func perAndArithmeticWordsAreSpokenOperators(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("25 USD/hr / 23 EUR/hr", "1"),
        .error("25 USD/hr to EUR/hr", "Exchange rates unavailable — check your connection.").offline,
        .error("2 celsius * 3m", "Multiplication of these unit values is not supported."),
        .display("1 / 1kg", "1 kg^-1"),
        .display("(2m)^2", "4 m²"),
        .display("5m * 4m to ft2", "215.2782083 ft²"),
        .display("2m * 30cm", "0.6 m²"),
        .display("2m * 3m * 4m to l", "24,000 L"),
        .display("1 ft³ to l", "28.31684659 L"),
        .display("1m3", "1,000 L"),
        .display("1cm3", "1 mL"),
        .display("1dm³ to l", "1 L"),
        .display("(2dm)^3 to l", "8 L"),
        .display("1dL to cl", "10 cL"),
        .display("3 * 2cl 5ml to ml", "75 mL"),
        .display("1 fl oz to ml", "29.57352956 mL"),
        .display("250ml to fl oz", "8.453505675 fl oz"),
        .display("2m * 30cm * 40cm to l", "240 L"),
        .display("pi * (10cm)^2 * 30cm to l", "9.424777961 L"),
        .display("4/3 * pi * (10cm)^3 to l", "4.188790205 L"),
        .display("500l / (2m * 1m) to cm", "25 cm"),
        .display("cbrt(8l) to cm", "20 cm"),
        .display("10l / 2min to l/min", "5 L/min"),
        .display("10l/min * 30s to l", "5 L"),
        .display("150l / 10l/min to duration", "15 min"),
        .display("1m³/h to l/min", "16.66666667 L/min"),
        .display("60l/min to m3/h", "3.6 m³/h"),
        .display("2gpm to l/min", "7.570823568 L/min"),
        .error("10l + 2l/min", "Cannot add Volume and Volume Flow Rate."),
        .noResult("1m3/x")
    ] as [Case])
    func volumesAndFlowRatesDerive(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("100 Mbps to MB/s", "12.5 MB/s"),
        .display("1 MiB/s to Mbps", "8.388608 Mbps"),
        .display("1GB / 10MB/s to s", "100 s"),
        .display("500 Mbps in MBps", "62.5 MBps"),
        .copy("500 Mbps in MBps", "62.5 MBps"),
        .expression("500 Mbps in MBps", "500 Mbps"),
        .badges("500 Mbps in MBps", source: "Megabits per Second", target: "Megabytes per Second"),
        .display("62.5 MBps to Mbps", "500 Mbps"),
        .display("500Mbps -> MBps", "62.5 MBps"),
        .display("500 Mbps → MBps", "62.5 MBps"),
        .display("8 bps to Bps", "1 Bps"),
        .display("8 Kbps to kBps", "1 kBps"),
        .display("1 KBps to kbps", "8 Kbps"),
        .display("1 Gbps to GBps", "0.125 GBps"),
        .display("1 TBps to Tbps", "8 Tbps"),
        .display("1 MBps to kBps", "1,000 kBps"),
        .display("1 GBps to MBps", "1,000 MBps"),
        .display("1 TBps to GBps", "1,000 GBps"),
        .display("1 MBps to MB/s", "1 MB/s"),
        .display("8 Mb/s to MBps", "1 MBps"),
        .display("1 MiB/s to MBps", "1.048576 MBps"),
        .display("MBps Mbps", "8 Mbps"),
        .display("1 Bps", "8 bps"),
        .display("1 kBps", "8 Kbps"),
        .display("1 MBps", "8 Mbps"),
        .display("1 GBps", "8 Gbps"),
        .display("1 TBps", "8 Tbps"),
        .display("500 Mbps + 62.5 MBps", "125 MBps"),
        .display("1GB / 10MBps to s", "100 s")
    ] as [Case])
    func bitAndByteRatesConvert(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("8kbit to B", "1,000 B"),
        .display("1um to nm", "1,000 nm"),
        .display("1 GHz to MHz", "1,000 MHz"),
        .display("500 microseconds to ms", "0.5 ms"),
        .display("1ton to kg", "1,000 kg"),
        .display("1stone to kg", "6.35029318 kg"),
        .display("1nmi to km", "1.852 km"),
        .display("1ukgal to l", "4.54609 L"),
        .display("1ukpint to ml", "568.26125 mL"),
        .display("100hp to kw", "74.56998716 kW"),
        .display("3000rpm to hz", "50 Hz"),
        .display("1btu to kj", "1.055055853 kJ"),
        .display("1lbf to n", "4.448221615 N")
    ] as [Case])
    func lessCommonUnitsConvert(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("3000px / 300ppi to inches", "10 in"),
        .display("5in * 300PPI", "1,500 px"),
        .copy("5in * 300ppi", "1500px"),
        .display("300ppi * 5in", "1,500 px"),
        .display("3000 pixels / 10in to ppi", "300 ppi"),
        .badges("3000px / 10in", source: "Expression", target: "Pixels per Inch"),
        .display("3000px / 300px/in to cm", "25.4 cm"),
        .display("300ppi to px/cm", "118.1102362 px/cm"),
        .display("100px/cm to ppi", "254 ppi"),
        .display("1px/mm to ppi", "25.4 ppi"),
        .display("100px/m * 1m", "100 px"),
        .display("300ppi", "118.1102362 px/cm"),
        .display("1920px * 1080px", "2,073,600 px²"),
        .display("sqrt(9px²)", "3 px"),
        .display("sqrt((3840px)^2 + (2160px)^2) / 27in", "163.1783089 ppi"),
        .display("(300ppi * 2.54cm) / 300px", "1"),
        .error("3000px to cm", "Cannot convert Pixels to Length."),
        .error("10px + 1in", "Cannot add Pixels and Length."),
        .noResult("3000px / 0ppi"),
        .noResult("pixels")
    ] as [Case])
    func pixelDensityRelatesPixelsToLength(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("16px to rem", "1 rem"),
        .display("1.5rem to px", "24 px"),
        .copy("1.5rem to px", "24px"),
        .copy("24px", "1.5rem"),
        .copy("2000rem", "32000px"),
        .copy("1rem + 8px", "24px"),
        .copy("300ppi to px/cm", "118.1102362 px/cm"),
        .display("rem to px", "16 px"),
        .display("rem px", "16 px"),
        .display("24px", "1.5 rem"),
        .badges("24px", source: "Pixels", target: "REM"),
        .display("2rem", "32 px"),
        .display("2em", "32 px"),
        .display("0.875 rems", "14 px"),
        .display("1em to rem", "1 rem"),
        .display("1rem + 8px", "24 px"),
        .display("8px + 1rem", "1.5 rem"),
        .display("2rem * 3", "6 rem"),
        .display("32px / 1rem", "2"),
        .display("48rem / 96ppi to in", "8 in"),
        .error("1rem to cm", "Cannot convert Pixels to Length."),
        .noResult("rem")
    ] as [Case])
    func aRemIsSixteenPixels(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("20m2 / 4m", "5 m"),
        .display("sqrt(25m2)", "5 m"),
        .display("cbrt(-8m3)", "-2 m"),
        .display("pi * (2m)^2 to m2", "12.56637061 m²"),
        .display("sin(30deg) * 10m", "5 m"),
        .display("100km / 2h to km/h", "50 km/h"),
        .display("90km/h * 20min to km", "30 km"),
        .display("100km / 50km/h to h", "2 hr"),
        .display("1GB / 100mbps to s", "80 s")
    ] as [Case])
    func powersAndRatesDeriveUnits(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("1500w * 2h to kwh", "3 kWh"),
        .display("5 watt * 3h 30min", "17.5 Wh"),
        .display("3h 30min * 5 watt", "17.5 Wh"),
        .display("5 watt * 3h 30min to kwh", "0.0175 kWh"),
        .display("5 watt * 3h 30min to j", "63,000 J"),
        .copy("5 watt * 3h 30min", "17.5 Wh"),
        .display("5w * 3h 30min + 2wh", "19.5 Wh"),
        .display("2kw * 3h 30min", "7 kWh"),
        .display("5w * 30s", "150 J"),
        .display("12V * 2A", "24 W"),
        .display("12V / 6ohm", "2 A"),
        .display("12V / 2A", "6 Ω"),
        .display("2A * 6Ω", "12 V"),
        .display("24W / 12V", "2 A"),
        .display("500mA * 3h 30min", "1,750 mAh"),
        .display("2000mAh / 500mA to hours", "4 hr"),
        .display("12V * 2Ah to wh", "24 Wh"),
        .display("10Wh / 5V to mah", "2,000 mAh"),
        .display("3600 coulombs to ah", "1 Ah"),
        .display("1mW to W", "0.001 W"),
        .display("500mA", "0.5 A"),
        .display("1MW to W", "1,000,000 W"),
        .display("1MWh to kwh", "1,000 kWh"),
        .display("1mΩ to ohm", "0.001 Ω"),
        .display("1MΩ to ohm", "1,000,000 Ω"),
        .display("2 * 5feet 3inches", "10.5 ft"),
        .display("90km / 1h 30min to km/h", "60 km/h"),
        .display("2 * 1h 30min 15s to s", "10,830 s"),
        .error("5w * 3h + 30min", "Cannot add Energy and Time."),
        .noResult("5w * 3h 30")
    ] as [Case])
    func energyPowerAndElectricityDerive(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10n / 2m2 to pa", "5 Pa"),
        .display("10m/s / 2s", "5 m/s²"),
        .display("2kg * 3m/s²", "6 N"),
        .display("1 / 20ms to hz", "50 Hz"),
        .display("100 / s to hz", "100 Hz"),
        .display("1000 / (3/s)", "333.3333333 s"),
        .display("65535 / (100/s) to minutes", "10.9225 min"),
        .display("1000 / 3 / s", "333.3333333 Hz"),
        .noResult("100 / sec"),
        .display("(1hr + 30min) to timespan", "1 hr 30 min"),
        .display("100km / 40km/h to duration", "2 hr 30 min"),
        .noResult("1m / 0s"),
        .display("(2m)^0.5", "1.414213562 m^0.5"),
        .display("sqrt(4kg)", "2 kg^0.5"),
        .noResult("1kg!")
    ] as [Case])
    func mechanicsAndFrequencyDerive(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10kg +", "10 kg"),
        .copy("10kg +", "10 kg"),
        .expression("10kg +", "10 kg +"),
        .badges("10kg +", source: "Expression", target: "Kilograms"),
        .noResult("10kg + nonsense"),
        .noResult("10unknown + 5unknown"),
        .noResult("10kg / 0"),
        .display("1234kg + 1kg", "1,235 kg"),
        .copy("1234kg + 1kg", "1235 kg")
    ] as [Case])
    func aPartialUnitExpressionKeepsItsUnit(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("1 deg", "0.01745329252 rad"),
        .expression("1 deg", "1 deg"),
        .badges("1 deg", source: "Degrees", target: "Radians"),
        .display("90 deg to rad", "1.570796327 rad"),
        .display("1 rad to deg", "57.29577951 deg"),
        .display("1 turn to deg", "360 deg"),
        .display("200 grad to deg", "180 deg")
    ] as [Case])
    func anglesConvert(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("day to s", "86,400 s"),
        .display("deg to rad", "0.01745329252 rad"),
        .display("m to ft", "3.280839895 ft"),
        .display("day s", "86,400 s"),
        .badges("day s", source: "Days", target: "Seconds"),
        .display("days s", "86,400 s"),
        .display("hr min", "60 min"),
        .noResult("m s")
    ] as [Case])
    func aNumberlessConversionImpliesOne(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("100 kmh to mph", "62.13711922 mph"),
        .display("60 mph to kmh", "96.56064 km/h"),
        .display("100 mbps to kbps", "100,000 Kbps"),
        .badges("100 kmh to mph", source: "Kilometers per Hour", target: "Miles per Hour")
    ] as [Case])
    func speedsAndDataRatesConvert(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("36 mpg", "15.30517347 km/L"),
        .badges("36 mpg", source: "Miles per Gallon", target: "Kilometers per Liter"),
        .display("15 km/l to mpg", "35.2821875 mpg"),
        .display("100 mi / 4 gal to mpg", "25 mpg"),
        .display("24.5 l / 350 km to l/100km", "7 L/100km"),
        .display("1 / 36 mpg to l/100km", "6.533738426 L/100km"),
        .display("30 mpg to l/100km", "7.840486111 L/100km"),
        .display("6.5 l/100km to mpg", "36.18685897 mpg"),
        .display("8 l/100km to km/l", "12.5 km/L"),
        .display("10 km/h to min/km", "6 min/km"),
        .display("6 min/km to km/h", "10 km/h"),
        .display("10 mph to min/mi", "6 min/mi"),
        .noResult("0 mpg to l/100km"),
        .error("1 hz to s", "Cannot convert Frequency to Time."),
        .error("10 km to min/km", "Cannot convert Length to Compound Units."),
        .error("10 mpg to kg", "Cannot convert Fuel Economy to Weight."),
        .error("1 m2 to mpg", "Cannot convert Area to Fuel Economy."),
        .error("10 mpg to m2", "Cannot convert Fuel Economy to Area."),
        .error("10 m2 to m^-2", "Cannot convert Area to Compound Units."),
        .error("1 ha to mpg", "Cannot convert Area to Fuel Economy."),
        .error("5m * 4m to mpg", "Cannot convert Area to Fuel Economy."),
        .display("100 mi / 4 gal to l/100km", "9.408583333 L/100km"),
        .display("24.5 l / 350 km to mpg", "33.60208333 mpg"),
        .display("(24.5 l / 350 km) to km/l", "14.28571429 km/L"),
        .noResult("0 mi / 4 gal to l/100km")
    ] as [Case])
    func fuelEconomyAndPaceInvert(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("5 mbar", "0.07251886887 psi"),
        .display("5 kPa", "0.7251886887 psi"),
        .display("5 hPa", "0.07251886887 psi"),
        .display("5 mmHg", "0.0966838873 psi"),
        .display("5 Torr", "0.09668387352 psi"),
        .display("100 bps", "0.1 Kbps"),
        .display("1 Tbps", "1,000 Gbps")
    ] as [Case])
    func pressureAndDataRatesPickATarget(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("100 km/h to mph", "62.13711922 mph"),
        .display("60 mph in km/h", "96.56064 km/h"),
        .display("5 m/s to km/h", "18 km/h"),
        .display("100 km/h", "62.13711922 mph"),
        .expression("100 km/h to mph", "100 km/h"),
        .badges("5 m/s to km/h", source: "Meters per Second", target: "Kilometers per Hour"),
        .display("100 mbit/s to mbps", "100 Mbps"),
        .display("10/2", "5"),
        .display("6/2(1+2)", "9"),
        .display("10 m / 2", "5 m"),
        .noResult("1 km/x")
    ] as [Case])
    func aKnownSlashedRateStaysWhole(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("55h in workdays", "6.875 workdays"),
        .display("3 workdays in hours", "24 hr"),
        .display("2 businessdays to hours", "16 hr"),
        .badges("55h in workdays", source: "Hours", target: "Workdays")
    ] as [Case])
    func aWorkdayIsEightHours(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("145 mins to timespan", "2 hr 25 min"),
        .display("1 month to timespan", "4 wk 2 day 10 hr 29 min 6 s"),
        .display("8700 s to timespan", "2 hr 25 min"),
        .display("90000 s to timespan", "1 day 1 hr"),
        .display("55 h to timespan", "2 day 7 hr"),
        .display("1000000 s to timespan", "1 wk 4 day 13 hr 46 min 40 s"),
        .badges("145 mins to timespan", source: "Minutes", target: "Timespan"),
        .noResult("10 km to timespan")
    ] as [Case])
    func aTimespanBreaksADuration(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }

    @Test(arguments: [
        .display("10kg to lb + 3lb", "25.04622622 lb"),
        .display("10kg to lb - 1lb", "21.04622622 lb"),
        .display("100 km/h to mph + 3mph", "65.13711922 mph"),
        .display("10km to mi + 3mi", "9.213711922 mi"),
        .display("10kg to lb + 3lb + 1lb", "26.04622622 lb"),
        .display("10km to mi + 3mi to km", "14.828032 km"),
        .display("10kg to lb + 3", "25.04622622 lb"),
        .error("1kg to m + 3", "Cannot convert Weight to Length."),
        .display("10kg + 500g to lb", "23.14853753 lb"),
        .display("1kg + 1kg to g", "2,000 g"),
        .display("2hr + 30min to min", "150 min")
    ] as [Case])
    func aTrailingToConvertsTheWholeExpression(_ row: Case) throws {
        #expect(try row.actual() == row.expected)
    }
}
