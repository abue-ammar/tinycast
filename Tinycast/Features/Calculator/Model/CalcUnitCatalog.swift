import Foundation

enum CalcUnitCatalog {
    static func makeIndex() -> [String: UnitDef] {
        var table: [String: UnitDef] = [:]
        table.reserveCapacity(1024)
        var category = UnitCategory.length
        func add(_ definition: UnitDef, _ names: [String]) {
            for name in names { table[name] = definition }
        }
        for line in records.split(separator: "\n") {
            let fields = line.split(separator: "|")
            if fields.count == 1 {
                guard let next = UnitCategory(rawValue: String(line)) else {
                    preconditionFailure("Invalid built-in unit category")
                }
                category = next
                continue
            }
            guard fields.count == 4 || fields.count == 5, let factor = Double(fields[2]),
                let offset = fields.count == 5 ? Double(fields[4]) : 0 else {
                preconditionFailure("Invalid built-in unit record")
            }
            let definition = UnitDef(String(fields[0]), String(fields[1]), category, factor, offset: offset)
            for name in fields[3].split(separator: ",") { table[String(name)] = definition }
        }

        for (prefix, name, factor) in [
            ("p", "Pico", 1e-12), ("n", "Nano", 1e-9), ("µ", "Micro", 1e-6), ("m", "Milli", 1e-3),
            ("c", "Centi", 1e-2), ("d", "Deci", 1e-1), ("k", "Kilo", 1e3), ("M", "Mega", 1e6),
            ("G", "Giga", 1e9), ("T", "Tera", 1e12), ("P", "Peta", 1e15)
        ] {
            for key in ["m", "g", "s", "hz", "n", "j", "w", "pa"] {
                guard let base = table[key] else { continue }
                let symbol = prefix + base.symbol
                let label = name + base.name.lowercased()
                let unit = UnitDef(symbol, label, base.category, base.factor * factor)
                let noun = label.lowercased()
                var aliases = [symbol, noun, noun.hasSuffix("s") ? String(noun.dropLast()) : noun]
                if prefix == "µ" { aliases += ["u" + base.symbol, "μ" + base.symbol] }
                for alias in aliases where table[alias] == nil { table[alias] = unit }
            }
        }

        for (prefix, label, factor) in [
            ("", "", 1.0), ("k", "Kilo", 1e3), ("M", "Mega", 1e6), ("G", "Giga", 1e9), ("T", "Tera", 1e12),
            ("Ki", "Kibi", 1024.0), ("Mi", "Mebi", 1048576.0), ("Gi", "Gibi", 1073741824.0),
            ("Ti", "Tebi", 1099511627776.0)
        ] {
            let bytes = prefix + "B/s"
            add(UnitDef(bytes, (label.isEmpty ? "Bytes" : label + "bytes") + " per Second", .dataRate, factor), [bytes])
            if !prefix.isEmpty {
                let bits = prefix + "bit"
                add(UnitDef(bits, label + "bits", .digitalStorage, factor / 8), [bits])
                let rate = bits + "/s"
                add(UnitDef(rate, label + "bits per Second", .dataRate, factor / 8), [rate])
            }
        }

        return table
    }

    // Category headers; records hold symbol, label, scale, aliases and optional offset.
    private static let records = """
    length
    mm|Millimeters|0.001|mm,millimeter,millimeters,millimetre,millimetres
    cm|Centimeters|0.01|cm,centimeter,centimeters,centimetre,centimetres
    dm|Decimeters|0.1|dm,decimeter,decimeters,decimetre,decimetres
    m|Meters|1.0|m,meter,meters,metre,metres
    km|Kilometers|1000.0|km,kilometer,kilometers,kilometre,kilometres
    in|Inches|0.0254|in,inch,inches
    ft|Feet|0.3048|ft,foot,feet
    yd|Yards|0.9144|yd,yard,yards
    mi|Miles|1609.344|mi,mile,miles
    nmi|Nautical Miles|1852.0|nmi,nauticalmile,nauticalmiles
    pixels
    px|Pixels|1.0|px,pixel,pixels
    pixelArea
    px²|Square Pixels|1.0|px2
    pixelDensity
    ppi|Pixels per Inch|39.37007874015748|ppi,px/in,px/inch,px/inches,pixels/inch
    px/cm|Pixels per Centimeter|100.0|px/cm
    px/mm|Pixels per Millimeter|1000.0|px/mm
    px/m|Pixels per Meter|1.0|px/m
    weight
    mg|Milligrams|1e-06|mg,milligram,milligrams
    g|Grams|0.001|g,gram,grams
    kg|Kilograms|1.0|kg,kilogram,kilograms,kilo,kilos
    oz|Ounces|0.028349523125|oz,ounce,ounces
    lb|Pounds|0.45359237|lb,lbs,pound,pounds
    t|Tonnes|1000.0|t,ton,tons,tonne,tonnes
    st|Stone|6.35029318|st,stone
    short ton|US Tons|907.18474|shortton,uston
    long ton|UK Tons|1016.0469088|longton,ukton
    temperature
    °C|Celsius|1.0|c,°c,celsius,centigrade|273.15
    °F|Fahrenheit|0.5555555555555556|f,°f,fahrenheit|255.3722222222222
    K|Kelvin|1.0|k,kelvin,kelvins
    time
    ms|Milliseconds|0.001|ms,millisecond,milliseconds
    s|Seconds|1.0|s,sec,secs,second,seconds
    min|Minutes|60.0|min,mins,minute,minutes
    hr|Hours|3600.0|h,hr,hrs,hour,hours
    day|Days|86400.0|d,day,days
    week|Weeks|604800.0|wk,week,weeks
    workdays|Workdays|28800.0|workday,workdays,businessday,businessdays
    area
    mm²|Square Millimeters|1e-06|mm2,sqmm
    cm²|Square Centimeters|0.0001|cm2,sqcm
    dm²|Square Decimeters|0.01|dm2,sqdm
    m²|Square Meters|1.0|m2,sqm
    km²|Square Kilometers|1000000.0|km2,sqkm
    in²|Square Inches|0.00064516|in2,sqin
    ft²|Square Feet|0.09290304|ft2,sqft
    yd²|Square Yards|0.83612736|yd2,sqyd
    mi²|Square Miles|2589988.110336|mi2,sqmi
    acre|Acres|4046.8564224|acre,acres
    ha|Hectares|10000.0|ha,hectare,hectares
    volume
    mL|Milliliters|1e-06|ml,milliliter,milliliters,millilitre,millilitres
    cL|Centiliters|1e-05|cl,centiliter,centiliters,centilitre,centilitres
    dL|Deciliters|0.0001|dl,deciliter,deciliters,decilitre,decilitres
    L|Liters|0.001|l,liter,liters,litre,litres
    cup|Cups|0.0002365882365|cup,cups
    tbsp|Tablespoons|1.478676478125e-05|tbsp,tablespoon,tablespoons
    tsp|Teaspoons|4.92892159375e-06|tsp,teaspoon,teaspoons
    gal|Gallons|0.003785411784|gal,gallon,gallons
    qt|Quarts|0.000946352946|qt,quart,quarts
    pt|Pints|0.000473176473|pt,pint,pints
    fl oz|Fluid Ounces|2.95735295625e-05|floz,fl oz
    mm³|Cubic Millimeters|1e-09|mm3
    cm³|Cubic Centimeters|1e-06|cm3,cc
    dm³|Cubic Decimeters|0.001|dm3
    m³|Cubic Meters|1.0|m3
    in³|Cubic Inches|1.6387064e-05|in3
    ft³|Cubic Feet|0.028316846592|ft3
    yd³|Cubic Yards|0.764554857984|yd3
    volumeFlow
    L/s|Liters per Second|0.001|l/s,l/sec
    L/min|Liters per Minute|1.6666666666666667e-05|l/min,lpm
    L/h|Liters per Hour|2.7777777777777776e-07|l/h,l/hr,lph
    m³/s|Cubic Meters per Second|1.0|m3/s,m3/sec
    m³/h|Cubic Meters per Hour|0.0002777777777777778|m3/h,m3/hr
    gal/min|Gallons per Minute|6.30901964e-05|gal/min,gpm
    digitalStorage
    bit|Bits|0.125|bit,bits
    B|Bytes|1.0|b,byte,bytes
    kB|Kilobytes|1000.0|kb,kilobyte,kilobytes
    MB|Megabytes|1000000.0|mb,megabyte,megabytes
    GB|Gigabytes|1000000000.0|gb,gigabyte,gigabytes
    TB|Terabytes|1000000000000.0|tb,terabyte,terabytes
    PB|Petabytes|1000000000000000.0|pb,petabyte,petabytes
    KiB|Kibibytes|1024.0|kib,kibibyte,kibibytes
    MiB|Mebibytes|1048576.0|mib,mebibyte,mebibytes
    GiB|Gibibytes|1073741824.0|gib,gibibyte,gibibytes
    TiB|Tebibytes|1099511627776.0|tib,tebibyte,tebibytes
    angle
    rad|Radians|1.0|rad,radian,radians
    deg|Degrees|0.017453292519943295|deg,degree,degrees
    grad|Gradians|0.015707963267948967|grad,grads,gradian,gradians,gon
    arcmin|Arcminutes|0.0002908882086657216|arcmin,arcminute,arcminutes
    arcsec|Arcseconds|4.84813681109536e-06|arcsec,arcsecond,arcseconds
    turn|Turns|6.283185307179586|turn,turns,rev,revolution,revolutions
    speed
    m/s|Meters per Second|1.0|mps,m/s,m/sec
    km/h|Kilometers per Hour|0.2777777777777778|kmh,kph,km/h,km/hr,kmph
    mph|Miles per Hour|0.44704|mph,mi/h,mi/hr
    ft/s|Feet per Second|0.3048|fps,ft/s,ft/sec
    kn|Knots|0.5144444444444445|kn,knot,knots
    km/s|Kilometers per Second|1000.0|km/s,km/sec
    pressure
    Pa|Pascals|1.0|pa,pascal,pascals
    hPa|Hectopascals|100.0|hpa
    kPa|Kilopascals|1000.0|kpa
    bar|Bar|100000.0|bar,bars
    mbar|Millibar|100.0|mbar,millibar,millibars
    psi|PSI|6894.757293168|psi
    atm|Atmospheres|101325.0|atm,atmosphere,atmospheres
    mmHg|Millimeters of Mercury|133.322387415|mmhg
    Torr|Torr|133.32236842105263|torr
    dataRate
    bps|Bits per Second|0.125|bps
    Kbps|Kilobits per Second|125.0|kbps,kbit/s,kb/s
    Mbps|Megabits per Second|125000.0|mbps,mbit/s,mb/s
    Gbps|Gigabits per Second|125000000.0|gbps,gbit/s,gb/s
    Tbps|Terabits per Second|125000000000.0|tbps,tbit/s,tb/s
    acceleration
    m/s²|Meters per Second Squared|1.0|m/s2,mps2
    force
    N|Newtons|1.0|n,newton,newtons
    energy
    J|Joules|1.0|j,joule,joules
    kJ|Kilojoules|1000.0|kj,kilojoule,kilojoules
    Wh|Watt Hours|3600.0|wh
    mWh|Milliwatt Hours|3.6|mwh
    kWh|Kilowatt Hours|3600000.0|kwh
    MWh|Megawatt Hours|3600000000.0|MWh,megawatthour,megawatthours
    cal|Calories|4.184|cal,calorie,calories
    kcal|Kilocalories|4184.0|kcal,kilocalorie,kilocalories
    power
    W|Watts|1.0|w,watt,watts
    mW|Milliwatts|0.001|mw,milliwatt,milliwatts
    kW|Kilowatts|1000.0|kw,kilowatt,kilowatts
    MW|Megawatts|1000000.0|MW,megawatt,megawatts
    electricCurrent
    A|Amperes|1.0|a,amp,amps,ampere,amperes
    mA|Milliamperes|0.001|ma,milliamp,milliamps,milliampere,milliamperes
    MA|Megaamperes|1000000.0|MA,megaamp,megaamps
    µA|Microamperes|1e-06|ua,µa,μa,microamp,microamps
    voltage
    V|Volts|1.0|v,volt,volts
    mV|Millivolts|0.001|mv,millivolt,millivolts
    kV|Kilovolts|1000.0|kv,kilovolt,kilovolts
    MV|Megavolts|1000000.0|MV,megavolt,megavolts
    resistance
    Ω|Ohms|1.0|ω,ohm,ohms
    mΩ|Milliohms|0.001|mω,milliohm,milliohms
    kΩ|Kilohms|1000.0|kω,kohm,kohms,kilohm,kilohms
    MΩ|Megohms|1000000.0|MΩ,megohm,megohms
    electricCharge
    As|Coulombs|1.0|as,coulomb,coulombs
    Ah|Ampere Hours|3600.0|ah,amphour,amphours
    mAh|Milliampere Hours|3.6|mah,milliamphour,milliamphours
    MAh|Megaampere Hours|3600000000.0|MAh
    frequency
    Hz|Hertz|1.0|hz,hertz
    kHz|Kilohertz|1000.0|khz,kilohertz
    MHz|Megahertz|1000000.0|mhz,megahertz
    volume
    UK gal|UK Gallons|0.00454609|ukgal,ukgallon,ukgallons
    UK qt|UK Quarts|0.0011365225|ukqt,ukquart,ukquarts
    UK pt|UK Pints|0.00056826125|ukpt,ukpint,ukpints
    UK fl oz|UK Fluid Ounces|2.84130625e-05|ukfloz
    power
    hp|Horsepower|745.6998715822702|hp,horsepower
    energy
    BTU|British Thermal Units|1055.05585262|btu
    frequency
    rpm|Revolutions per Minute|0.016666666666666666|rpm
    force
    lbf|Pounds Force|4.4482216152605|lbf,poundforce
    """
}
