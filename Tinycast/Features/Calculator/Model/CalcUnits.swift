import Foundation

enum UnitCategory: String, CaseIterable, Sendable {
    case length, weight, temperature, time, area, volume, digitalStorage
    case angle, speed, pressure, dataRate, acceleration, force, energy, power, frequency
    case electricCurrent, voltage, resistance, electricCharge, volumeFlow
    case pixels, pixelArea, pixelDensity

    var displayName: String {
        switch self {
        case .length: return "Length"
        case .weight: return "Weight"
        case .temperature: return "Temperature"
        case .time: return "Time"
        case .area: return "Area"
        case .volume: return "Volume"
        case .digitalStorage: return "Digital Storage"
        case .angle: return "Angle"
        case .speed: return "Speed"
        case .pressure: return "Pressure"
        case .dataRate: return "Data Transfer Rate"
        case .acceleration: return "Acceleration"
        case .force: return "Force"
        case .energy: return "Energy"
        case .power: return "Power"
        case .frequency: return "Frequency"
        case .electricCurrent: return "Electric Current"
        case .voltage: return "Voltage"
        case .resistance: return "Resistance"
        case .electricCharge: return "Electric Charge"
        case .volumeFlow: return "Volume Flow Rate"
        case .pixels: return "Pixels"
        case .pixelArea: return "Pixel Area"
        case .pixelDensity: return "Pixel Density"
        }
    }

    var dimension: CalcDimension? {
        switch self {
        case .length: return CalcDimension(length: 1)
        case .weight: return CalcDimension(mass: 1)
        case .time: return CalcDimension(time: 1)
        case .area: return CalcDimension(length: 2)
        case .volume: return CalcDimension(length: 3)
        case .digitalStorage: return CalcDimension(data: 1)
        case .speed: return CalcDimension(length: 1, time: -1)
        case .pressure: return CalcDimension(length: -1, mass: 1, time: -2)
        case .dataRate: return CalcDimension(time: -1, data: 1)
        case .acceleration: return CalcDimension(length: 1, time: -2)
        case .force: return CalcDimension(length: 1, mass: 1, time: -2)
        case .energy: return CalcDimension(length: 2, mass: 1, time: -2)
        case .power: return CalcDimension(length: 2, mass: 1, time: -3)
        case .frequency: return CalcDimension(time: -1)
        case .electricCurrent: return CalcDimension(electricCurrent: 1)
        case .voltage: return CalcDimension(length: 2, mass: 1, time: -3, electricCurrent: -1)
        case .resistance: return CalcDimension(length: 2, mass: 1, time: -3, electricCurrent: -2)
        case .electricCharge: return CalcDimension(time: 1, electricCurrent: 1)
        case .volumeFlow: return CalcDimension(length: 3, time: -1)
        case .pixels: return CalcDimension(pixels: 1)
        case .pixelArea: return CalcDimension(pixels: 2)
        case .pixelDensity: return CalcDimension(length: -1, pixels: 1)
        case .temperature, .angle: return nil
        }
    }
}

/// A unit as an affine map onto its base: `base = value * factor + offset`. Temperature only.
struct UnitDef: Equatable, Sendable {
    let symbol: String  // canonical display form: "mi", "°F", "GiB"
    let name: String  // long label for the card badge: "Miles", "Fahrenheit"
    let category: UnitCategory
    let factor: Double
    let offset: Double

    init(_ symbol: String, _ name: String, _ category: UnitCategory, _ factor: Double, offset: Double = 0) {
        self.symbol = symbol
        self.name = name
        self.category = category
        self.factor = factor
        self.offset = offset
    }
}

enum CalcUnits {
    static let baseUnits: [CalcDimension: UnitDef] = {
        var units: [CalcDimension: UnitDef] = [:]
        for name in [
            "m", "kg", "s", "m2", "m3", "b", "m/s", "pa", "bps", "m/s2", "n", "j", "w", "hz",
            "a", "v", "ohm", "as", "m3/s", "px", "px2", "ppi"
        ] {
            if let unit = byName[name], let dimension = unit.category.dimension {
                units[dimension] = unit
            }
        }
        return units
    }()

    static func productUnit(_ lhs: UnitDef, _ rhs: UnitDef) -> UnitDef? {
        let (measure, duration) = lhs.category == .time ? (rhs, lhs) : (lhs, rhs)
        guard duration.category == .time, duration.factor >= 60 else { return nil }
        switch measure.category {
        case .power: return byName[measure.factor >= 1000 ? "kwh" : "wh"]
        case .electricCurrent: return byName[measure.factor <= 0.001 ? "mah" : "ah"]
        default: return nil
        }
    }

    enum ConversionParse: Equatable {
        case value(input: Double, from: UnitDef, to: UnitDef, output: Double)
        case mismatch(from: UnitDef, to: UnitDef)
    }

    /// A keyword-less conversion to a curated counterpart; `compound` asks for feet+inches.
    struct BareConversion: Equatable {
        let input: Double
        let from: UnitDef
        let to: UnitDef
        let output: Double
        let compound: Bool
    }

    /// `expr unit (to|in|->) unit`. Matching the last position lets "in" double as inches.
    static func parseConversion(_ tokens: [CalcToken]) -> ConversionParse? {
        guard tokens.count >= 3, isConnector(tokens[tokens.count - 2]),
            case .ident(let toName) = tokens[tokens.count - 1],
            let to = byName[toName],
            case .ident(let fromName) = tokens[tokens.count - 3],
            let from = byName[fromName]
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 3)])
        let input: Double
        if valueTokens.isEmpty {
            input = 1
        } else if let value = CalcParser.evaluate(valueTokens) {
            input = value
        } else {
            return nil
        }

        guard from.category == to.category else { return .mismatch(from: from, to: to) }
        let output = (input * from.factor + from.offset - to.offset) / to.factor
        guard output.isFinite else { return nil }
        return .value(input: input, from: from, to: to, output: output)
    }

    /// `day s` → `1 day` in `s`. Same category only, so two-word searches don't produce a card.
    static func parseUnitPairConversion(_ tokens: [CalcToken]) -> ConversionParse? {
        guard tokens.count == 2,
            case .ident(let fromName) = tokens[0], let from = byName[fromName],
            case .ident(let toName) = tokens[1], let to = byName[toName],
            from.category == to.category
        else { return nil }

        let output = (1 * from.factor + from.offset - to.offset) / to.factor
        guard output.isFinite else { return nil }
        return .value(input: 1, from: from, to: to, output: output)
    }

    /// `expr unit` with no connector. c/f/k are excluded, so `5k` stays an app search.
    static func parseBareConversion(_ tokens: [CalcToken]) -> BareConversion? {
        guard tokens.count >= 2, case .ident(let fromName) = tokens[tokens.count - 1],
            !["c", "f", "k"].contains(fromName),
            let from = byName[fromName],
            let mapping = autoTargets[from.symbol],
            let to = byName[mapping.to]
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 1)])
        guard let input = CalcParser.evaluate(valueTokens) else { return nil }

        let output = (input * from.factor + from.offset - to.offset) / to.factor
        guard output.isFinite else { return nil }
        return BareConversion(input: input, from: from, to: to, output: output, compound: mapping.compound)
    }

    static func isConnector(_ token: CalcToken) -> Bool {
        switch token {
        case .arrow, .ident("to"), .ident("in"): return true
        default: return false
        }
    }

    /// Keyword-less counterpart per unit; only `m→ft` is compound.
    static let autoTargets: [String: (to: String, compound: Bool)] = [
        // Length
        "mm": ("in", false), "cm": ("in", false), "m": ("ft", true), "km": ("mi", false),
        "dm": ("cm", false), "in": ("cm", false), "ft": ("m", false), "yd": ("m", false), "mi": ("km", false),
        // Weight
        "mg": ("g", false), "g": ("oz", false), "kg": ("lb", false), "oz": ("g", false),
        "lb": ("kg", false),
        // Temperature (bare form requires a spelled/°-prefixed alias — see parseBareConversion)
        "°C": ("f", false), "°F": ("c", false), "K": ("c", false),
        // Time
        "ms": ("s", false), "s": ("ms", false), "min": ("s", false), "hr": ("min", false),
        "day": ("hr", false), "week": ("day", false),
        "workdays": ("hr", false),
        // Area
        "mm²": ("in2", false), "cm²": ("in2", false), "m²": ("ft2", false), "km²": ("mi2", false),
        "in²": ("cm2", false), "ft²": ("m2", false), "yd²": ("m2", false), "mi²": ("km2", false),
        "acre": ("m2", false), "ha": ("acre", false),
        "dm²": ("cm2", false),
        // Volume
        "mL": ("floz", false), "L": ("gal", false), "cup": ("ml", false), "tbsp": ("ml", false),
        "tsp": ("ml", false), "gal": ("l", false), "qt": ("l", false), "pt": ("ml", false),
        "fl oz": ("ml", false),
        "cL": ("ml", false), "dL": ("ml", false),
        "mm³": ("ml", false), "cm³": ("ml", false), "dm³": ("l", false), "m³": ("l", false),
        "in³": ("ml", false), "ft³": ("l", false), "yd³": ("l", false),
        "L/s": ("l/min", false), "L/min": ("l/h", false), "L/h": ("l/min", false),
        "m³/s": ("l/s", false), "m³/h": ("l/min", false), "gal/min": ("l/min", false),
        // Digital storage
        "bit": ("b", false), "B": ("bit", false), "kB": ("kib", false), "MB": ("mib", false),
        "GB": ("gib", false), "TB": ("tib", false), "PB": ("tb", false), "KiB": ("kb", false),
        "MiB": ("mb", false), "GiB": ("gb", false), "TiB": ("tb", false),
        // Angle
        "deg": ("rad", false), "rad": ("deg", false), "grad": ("deg", false),
        "turn": ("deg", false), "arcmin": ("deg", false), "arcsec": ("deg", false),
        // Speed
        "km/h": ("mph", false), "mph": ("kmh", false), "m/s": ("kmh", false),
        "kn": ("kmh", false), "ft/s": ("mph", false),
        // Pressure
        "bar": ("psi", false), "psi": ("bar", false), "atm": ("psi", false),
        "mbar": ("psi", false), "kPa": ("psi", false), "hPa": ("psi", false),
        "mmHg": ("psi", false), "Torr": ("psi", false),
        // Data transfer rate
        "Mbps": ("kbps", false), "Gbps": ("mbps", false), "Kbps": ("bps", false),
        "bps": ("kbps", false), "Tbps": ("gbps", false),
        "Wh": ("kwh", false), "mWh": ("wh", false), "kWh": ("wh", false), "MWh": ("kwh", false),
        "W": ("kw", false), "mW": ("w", false), "kW": ("w", false), "MW": ("kw", false),
        "A": ("ma", false), "mA": ("a", false), "µA": ("ma", false), "MA": ("a", false),
        "V": ("mv", false), "mV": ("v", false), "kV": ("v", false), "MV": ("kv", false),
        "Ω": ("kohm", false), "mΩ": ("ohm", false), "kΩ": ("ohm", false), "MΩ": ("kohm", false),
        "As": ("ah", false), "Ah": ("mah", false), "mAh": ("ah", false), "MAh": ("ah", false),
        "ppi": ("px/cm", false), "px/cm": ("ppi", false),
        "px/mm": ("ppi", false), "px/m": ("ppi", false)
    ]

    static let byName: [String: UnitDef] = {
        var table: [String: UnitDef] = [:]
        func add(_ def: UnitDef, _ names: [String]) {
            for name in names { table[name] = def }
        }

        // Length (base: meter)
        add(
            UnitDef("mm", "Millimeters", .length, 0.001),
            ["mm", "millimeter", "millimeters", "millimetre", "millimetres"])
        add(
            UnitDef("cm", "Centimeters", .length, 0.01),
            ["cm", "centimeter", "centimeters", "centimetre", "centimetres"])
        add(
            UnitDef("dm", "Decimeters", .length, 0.1),
            ["dm", "decimeter", "decimeters", "decimetre", "decimetres"])
        add(UnitDef("m", "Meters", .length, 1), ["m", "meter", "meters", "metre", "metres"])
        add(
            UnitDef("km", "Kilometers", .length, 1000),
            ["km", "kilometer", "kilometers", "kilometre", "kilometres"])
        add(UnitDef("in", "Inches", .length, 0.0254), ["in", "inch", "inches"])
        add(UnitDef("ft", "Feet", .length, 0.3048), ["ft", "foot", "feet"])
        add(UnitDef("yd", "Yards", .length, 0.9144), ["yd", "yard", "yards"])
        add(UnitDef("mi", "Miles", .length, 1609.344), ["mi", "mile", "miles"])
        add(UnitDef("nmi", "Nautical Miles", .length, 1852), ["nmi", "nauticalmile", "nauticalmiles"])

        add(UnitDef("px", "Pixels", .pixels, 1), ["px", "pixel", "pixels"])
        add(UnitDef("px²", "Square Pixels", .pixelArea, 1), ["px2"])
        add(
            UnitDef("ppi", "Pixels per Inch", .pixelDensity, 1 / 0.0254),
            ["ppi", "px/in", "px/inch", "px/inches", "pixels/inch"])
        add(UnitDef("px/cm", "Pixels per Centimeter", .pixelDensity, 100), ["px/cm"])
        add(UnitDef("px/mm", "Pixels per Millimeter", .pixelDensity, 1000), ["px/mm"])
        add(UnitDef("px/m", "Pixels per Meter", .pixelDensity, 1), ["px/m"])

        // Weight (base: kilogram)
        add(UnitDef("mg", "Milligrams", .weight, 1e-6), ["mg", "milligram", "milligrams"])
        add(UnitDef("g", "Grams", .weight, 0.001), ["g", "gram", "grams"])
        add(
            UnitDef("kg", "Kilograms", .weight, 1),
            ["kg", "kilogram", "kilograms", "kilo", "kilos"])
        add(UnitDef("oz", "Ounces", .weight, 0.028349523125), ["oz", "ounce", "ounces"])
        add(UnitDef("lb", "Pounds", .weight, 0.45359237), ["lb", "lbs", "pound", "pounds"])
        add(UnitDef("t", "Tonnes", .weight, 1000), ["t", "ton", "tons", "tonne", "tonnes"])
        add(UnitDef("st", "Stone", .weight, 6.35029318), ["st", "stone"])
        add(UnitDef("short ton", "US Tons", .weight, 907.18474), ["shortton", "uston"])
        add(UnitDef("long ton", "UK Tons", .weight, 1016.0469088), ["longton", "ukton"])

        // Temperature (base: Kelvin) — the only affine category.
        add(
            UnitDef("°C", "Celsius", .temperature, 1, offset: 273.15),
            ["c", "°c", "celsius", "centigrade"])
        add(
            UnitDef("°F", "Fahrenheit", .temperature, 5.0 / 9.0, offset: 273.15 - 32 * 5.0 / 9.0),
            ["f", "°f", "fahrenheit"])
        add(UnitDef("K", "Kelvin", .temperature, 1), ["k", "kelvin", "kelvins"])

        // Time (base: second)
        add(UnitDef("ms", "Milliseconds", .time, 0.001), ["ms", "millisecond", "milliseconds"])
        add(UnitDef("s", "Seconds", .time, 1), ["s", "sec", "secs", "second", "seconds"])
        add(UnitDef("min", "Minutes", .time, 60), ["min", "mins", "minute", "minutes"])
        add(UnitDef("hr", "Hours", .time, 3600), ["h", "hr", "hrs", "hour", "hours"])
        add(UnitDef("day", "Days", .time, 86400), ["d", "day", "days"])
        add(UnitDef("week", "Weeks", .time, 604800), ["wk", "week", "weeks"])
        // 8 hours; weekends and holidays would need a calendar, and a calculator must not ask.
        add(
            UnitDef("workdays", "Workdays", .time, 28800),
            ["workday", "workdays", "businessday", "businessdays"])

        // Area (base: square meter). The tokenizer folds "²" to "2", so mm²/mm2 are one name.
        add(UnitDef("mm²", "Square Millimeters", .area, 1e-6), ["mm2", "sqmm"])
        add(UnitDef("cm²", "Square Centimeters", .area, 1e-4), ["cm2", "sqcm"])
        add(UnitDef("dm²", "Square Decimeters", .area, 0.01), ["dm2", "sqdm"])
        add(UnitDef("m²", "Square Meters", .area, 1), ["m2", "sqm"])
        add(UnitDef("km²", "Square Kilometers", .area, 1e6), ["km2", "sqkm"])
        add(UnitDef("in²", "Square Inches", .area, 0.00064516), ["in2", "sqin"])
        add(UnitDef("ft²", "Square Feet", .area, 0.09290304), ["ft2", "sqft"])
        add(UnitDef("yd²", "Square Yards", .area, 0.83612736), ["yd2", "sqyd"])
        add(UnitDef("mi²", "Square Miles", .area, 2_589_988.110336), ["mi2", "sqmi"])
        add(UnitDef("acre", "Acres", .area, 4046.8564224), ["acre", "acres"])
        add(UnitDef("ha", "Hectares", .area, 10000), ["ha", "hectare", "hectares"])

        // Volume (base: cubic meter; US customary)
        add(
            UnitDef("mL", "Milliliters", .volume, 1e-6),
            ["ml", "milliliter", "milliliters", "millilitre", "millilitres"])
        add(
            UnitDef("cL", "Centiliters", .volume, 1e-5),
            ["cl", "centiliter", "centiliters", "centilitre", "centilitres"])
        add(
            UnitDef("dL", "Deciliters", .volume, 1e-4),
            ["dl", "deciliter", "deciliters", "decilitre", "decilitres"])
        add(UnitDef("L", "Liters", .volume, 0.001), ["l", "liter", "liters", "litre", "litres"])
        add(UnitDef("cup", "Cups", .volume, 0.0002365882365), ["cup", "cups"])
        add(
            UnitDef("tbsp", "Tablespoons", .volume, 0.00001478676478125),
            ["tbsp", "tablespoon", "tablespoons"])
        add(
            UnitDef("tsp", "Teaspoons", .volume, 0.00000492892159375),
            ["tsp", "teaspoon", "teaspoons"])
        add(UnitDef("gal", "Gallons", .volume, 0.003785411784), ["gal", "gallon", "gallons"])
        add(UnitDef("qt", "Quarts", .volume, 0.000946352946), ["qt", "quart", "quarts"])
        add(UnitDef("pt", "Pints", .volume, 0.000473176473), ["pt", "pint", "pints"])
        add(UnitDef("fl oz", "Fluid Ounces", .volume, 0.0000295735295625), ["floz", "fl oz"])

        add(UnitDef("mm³", "Cubic Millimeters", .volume, 1e-9), ["mm3"])
        add(UnitDef("cm³", "Cubic Centimeters", .volume, 1e-6), ["cm3", "cc"])
        add(UnitDef("dm³", "Cubic Decimeters", .volume, 0.001), ["dm3"])
        add(UnitDef("m³", "Cubic Meters", .volume, 1), ["m3"])
        add(UnitDef("in³", "Cubic Inches", .volume, 0.000016387064), ["in3"])
        add(UnitDef("ft³", "Cubic Feet", .volume, 0.028316846592), ["ft3"])
        add(UnitDef("yd³", "Cubic Yards", .volume, 0.764554857984), ["yd3"])

        add(UnitDef("L/s", "Liters per Second", .volumeFlow, 0.001), ["l/s", "l/sec"])
        add(UnitDef("L/min", "Liters per Minute", .volumeFlow, 0.001 / 60), ["l/min", "lpm"])
        add(UnitDef("L/h", "Liters per Hour", .volumeFlow, 0.001 / 3600), ["l/h", "l/hr", "lph"])
        add(UnitDef("m³/s", "Cubic Meters per Second", .volumeFlow, 1), ["m3/s", "m3/sec"])
        add(UnitDef("m³/h", "Cubic Meters per Hour", .volumeFlow, 1.0 / 3600), ["m3/h", "m3/hr"])
        add(UnitDef("gal/min", "Gallons per Minute", .volumeFlow, 0.003785411784 / 60), ["gal/min", "gpm"])

        // Digital storage (base: byte): kB/MB are SI (1000ⁿ), KiB/MiB are IEC (1024ⁿ).
        add(UnitDef("bit", "Bits", .digitalStorage, 0.125), ["bit", "bits"])
        add(UnitDef("B", "Bytes", .digitalStorage, 1), ["b", "byte", "bytes"])
        add(UnitDef("kB", "Kilobytes", .digitalStorage, 1e3), ["kb", "kilobyte", "kilobytes"])
        add(UnitDef("MB", "Megabytes", .digitalStorage, 1e6), ["mb", "megabyte", "megabytes"])
        add(UnitDef("GB", "Gigabytes", .digitalStorage, 1e9), ["gb", "gigabyte", "gigabytes"])
        add(UnitDef("TB", "Terabytes", .digitalStorage, 1e12), ["tb", "terabyte", "terabytes"])
        add(UnitDef("PB", "Petabytes", .digitalStorage, 1e15), ["pb", "petabyte", "petabytes"])
        add(UnitDef("KiB", "Kibibytes", .digitalStorage, 1024), ["kib", "kibibyte", "kibibytes"])
        add(
            UnitDef("MiB", "Mebibytes", .digitalStorage, 1_048_576),
            ["mib", "mebibyte", "mebibytes"])
        add(
            UnitDef("GiB", "Gibibytes", .digitalStorage, 1_073_741_824),
            ["gib", "gibibyte", "gibibytes"])
        add(
            UnitDef("TiB", "Tebibytes", .digitalStorage, 1_099_511_627_776),
            ["tib", "tebibyte", "tebibytes"])

        // Angle (base: radian); `deg` is also a trig postfix, so conversion needs a lone `<n> deg`.
        add(UnitDef("rad", "Radians", .angle, 1), ["rad", "radian", "radians"])
        add(UnitDef("deg", "Degrees", .angle, .pi / 180), ["deg", "degree", "degrees"])
        add(UnitDef("grad", "Gradians", .angle, .pi / 200), ["grad", "grads", "gradian", "gradians", "gon"])
        add(UnitDef("arcmin", "Arcminutes", .angle, .pi / 10800), ["arcmin", "arcminute", "arcminutes"])
        add(UnitDef("arcsec", "Arcseconds", .angle, .pi / 648000), ["arcsec", "arcsecond", "arcseconds"])
        add(UnitDef("turn", "Turns", .angle, 2 * .pi), ["turn", "turns", "rev", "revolution", "revolutions"])

        // Speed (base: meter/second) — a slashed spelling stays whole, so it is a name.
        add(UnitDef("m/s", "Meters per Second", .speed, 1), ["mps", "m/s", "m/sec"])
        add(
            UnitDef("km/h", "Kilometers per Hour", .speed, 1000.0 / 3600),
            ["kmh", "kph", "km/h", "km/hr", "kmph"])
        add(UnitDef("mph", "Miles per Hour", .speed, 1609.344 / 3600), ["mph", "mi/h", "mi/hr"])
        add(UnitDef("ft/s", "Feet per Second", .speed, 0.3048), ["fps", "ft/s", "ft/sec"])
        add(UnitDef("kn", "Knots", .speed, 1852.0 / 3600), ["kn", "knot", "knots"])
        add(UnitDef("km/s", "Kilometers per Second", .speed, 1000), ["km/s", "km/sec"])

        // Pressure (base: pascal)
        add(UnitDef("Pa", "Pascals", .pressure, 1), ["pa", "pascal", "pascals"])
        add(UnitDef("hPa", "Hectopascals", .pressure, 100), ["hpa"])
        add(UnitDef("kPa", "Kilopascals", .pressure, 1000), ["kpa"])
        add(UnitDef("bar", "Bar", .pressure, 100000), ["bar", "bars"])
        add(UnitDef("mbar", "Millibar", .pressure, 100), ["mbar", "millibar", "millibars"])
        add(UnitDef("psi", "PSI", .pressure, 6894.757293168), ["psi"])
        add(UnitDef("atm", "Atmospheres", .pressure, 101325), ["atm", "atmosphere", "atmospheres"])
        add(UnitDef("mmHg", "Millimeters of Mercury", .pressure, 133.322387415), ["mmhg"])
        add(UnitDef("Torr", "Torr", .pressure, 101325.0 / 760), ["torr"])

        // Data transfer rate (base: byte/second) — SI (1000ⁿ) bit rates.
        add(UnitDef("bps", "Bits per Second", .dataRate, 1 / 8), ["bps"])
        add(UnitDef("Kbps", "Kilobits per Second", .dataRate, 1e3 / 8), ["kbps", "kbit/s", "kb/s"])
        add(UnitDef("Mbps", "Megabits per Second", .dataRate, 1e6 / 8), ["mbps", "mbit/s", "mb/s"])
        add(UnitDef("Gbps", "Gigabits per Second", .dataRate, 1e9 / 8), ["gbps", "gbit/s", "gb/s"])
        add(UnitDef("Tbps", "Terabits per Second", .dataRate, 1e12 / 8), ["tbps", "tbit/s", "tb/s"])

        add(UnitDef("m/s²", "Meters per Second Squared", .acceleration, 1), ["m/s2", "mps2"])
        add(UnitDef("N", "Newtons", .force, 1), ["n", "newton", "newtons"])
        add(UnitDef("J", "Joules", .energy, 1), ["j", "joule", "joules"])
        add(UnitDef("kJ", "Kilojoules", .energy, 1000), ["kj", "kilojoule", "kilojoules"])
        add(UnitDef("Wh", "Watt Hours", .energy, 3600), ["wh"])
        add(UnitDef("mWh", "Milliwatt Hours", .energy, 3.6), ["mwh"])
        add(UnitDef("kWh", "Kilowatt Hours", .energy, 3_600_000), ["kwh"])
        add(UnitDef("MWh", "Megawatt Hours", .energy, 3.6e9), ["MWh", "megawatthour", "megawatthours"])
        add(UnitDef("cal", "Calories", .energy, 4.184), ["cal", "calorie", "calories"])
        add(UnitDef("kcal", "Kilocalories", .energy, 4184), ["kcal", "kilocalorie", "kilocalories"])
        add(UnitDef("W", "Watts", .power, 1), ["w", "watt", "watts"])
        add(UnitDef("mW", "Milliwatts", .power, 0.001), ["mw", "milliwatt", "milliwatts"])
        add(UnitDef("kW", "Kilowatts", .power, 1000), ["kw", "kilowatt", "kilowatts"])
        add(UnitDef("MW", "Megawatts", .power, 1e6), ["MW", "megawatt", "megawatts"])
        add(UnitDef("A", "Amperes", .electricCurrent, 1), ["a", "amp", "amps", "ampere", "amperes"])
        add(
            UnitDef("mA", "Milliamperes", .electricCurrent, 0.001),
            ["ma", "milliamp", "milliamps", "milliampere", "milliamperes"])
        add(UnitDef("MA", "Megaamperes", .electricCurrent, 1e6), ["MA", "megaamp", "megaamps"])
        add(UnitDef("µA", "Microamperes", .electricCurrent, 1e-6), ["ua", "µa", "μa", "microamp", "microamps"])
        add(UnitDef("V", "Volts", .voltage, 1), ["v", "volt", "volts"])
        add(UnitDef("mV", "Millivolts", .voltage, 0.001), ["mv", "millivolt", "millivolts"])
        add(UnitDef("kV", "Kilovolts", .voltage, 1000), ["kv", "kilovolt", "kilovolts"])
        add(UnitDef("MV", "Megavolts", .voltage, 1e6), ["MV", "megavolt", "megavolts"])
        add(UnitDef("Ω", "Ohms", .resistance, 1), ["ω", "ohm", "ohms"])
        add(UnitDef("mΩ", "Milliohms", .resistance, 0.001), ["mω", "milliohm", "milliohms"])
        add(UnitDef("kΩ", "Kilohms", .resistance, 1000), ["kω", "kohm", "kohms", "kilohm", "kilohms"])
        add(UnitDef("MΩ", "Megohms", .resistance, 1e6), ["MΩ", "megohm", "megohms"])
        add(UnitDef("As", "Coulombs", .electricCharge, 1), ["as", "coulomb", "coulombs"])
        add(UnitDef("Ah", "Ampere Hours", .electricCharge, 3600), ["ah", "amphour", "amphours"])
        add(UnitDef("mAh", "Milliampere Hours", .electricCharge, 3.6), ["mah", "milliamphour", "milliamphours"])
        add(UnitDef("MAh", "Megaampere Hours", .electricCharge, 3.6e9), ["MAh"])
        add(UnitDef("Hz", "Hertz", .frequency, 1), ["hz", "hertz"])
        add(UnitDef("kHz", "Kilohertz", .frequency, 1000), ["khz", "kilohertz"])
        add(UnitDef("MHz", "Megahertz", .frequency, 1e6), ["mhz", "megahertz"])

        add(UnitDef("UK gal", "UK Gallons", .volume, 0.00454609), ["ukgal", "ukgallon", "ukgallons"])
        add(UnitDef("UK qt", "UK Quarts", .volume, 0.0011365225), ["ukqt", "ukquart", "ukquarts"])
        add(UnitDef("UK pt", "UK Pints", .volume, 0.00056826125), ["ukpt", "ukpint", "ukpints"])
        add(UnitDef("UK fl oz", "UK Fluid Ounces", .volume, 0.0000284130625), ["ukfloz"])
        add(UnitDef("hp", "Horsepower", .power, 745.6998715822702), ["hp", "horsepower"])
        add(UnitDef("BTU", "British Thermal Units", .energy, 1055.05585262), ["btu"])
        add(UnitDef("rpm", "Revolutions per Minute", .frequency, 1.0 / 60), ["rpm"])
        add(UnitDef("lbf", "Pounds Force", .force, 4.4482216152605), ["lbf", "poundforce"])

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
    }()
}
