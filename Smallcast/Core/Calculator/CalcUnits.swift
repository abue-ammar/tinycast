import Foundation

enum UnitCategory: String, CaseIterable, Sendable {
    case length, weight, temperature, time, area, volume, digitalStorage
    case angle, speed, pressure, dataRate

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
        }
    }
}

/// One unit as an affine map onto its category's base unit (`base = value * factor + offset`); `offset` is nonzero only for temperature, so °C/°F/K convert with no special-casing. `name` is the long human label shown as a card badge ("Meters").
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
    enum ConversionParse: Equatable {
        case value(input: Double, from: UnitDef, to: UnitDef, output: Double)
        case mismatch(from: UnitDef, to: UnitDef)
    }

    /// A keyword-less conversion (`1m`, `1hr`) resolved to a curated counterpart unit; `compound` requests feet+inches formatting.
    struct BareConversion: Equatable {
        let input: Double
        let from: UnitDef
        let to: UnitDef
        let output: Double
        let compound: Bool
    }

    /// Detects `expr unit (to|in|->) unit` (connector second-to-last, known unit last), returning `.mismatch` only when both units are known but incompatible; matching the last position lets "in" double as inches. A missing value defaults to 1, so `day to s` reads as `1 day to s`.
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

    /// A no-connector two-unit query (`day s`, `km mi`) → `1 <first>` in `<second>`. Both must be known units in the same category; anything else returns nil so coincidental two-word searches don't produce a card.
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

    /// Detects `expr unit` with no connector (`1m`, `2*3 kg`) and converts to a curated counterpart from `autoTargets`. Single-letter temperature aliases (c/f/k) are excluded so `5k` stays an app search rather than "5 Kelvin".
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

    /// Keyword-less counterpart per unit (metric↔imperial where it applies): source `symbol` → target `byName` key + whether to render feet+inches. Only `m→ft` is compound.
    static let autoTargets: [String: (to: String, compound: Bool)] = [
        // Length
        "mm": ("in", false), "cm": ("in", false), "m": ("ft", true), "km": ("mi", false),
        "in": ("cm", false), "ft": ("m", false), "yd": ("m", false), "mi": ("km", false),
        // Weight
        "mg": ("g", false), "g": ("oz", false), "kg": ("lb", false), "oz": ("g", false),
        "lb": ("kg", false),
        // Temperature (bare form requires a spelled/°-prefixed alias — see parseBareConversion)
        "°C": ("f", false), "°F": ("c", false), "K": ("c", false),
        // Time
        "ms": ("s", false), "s": ("ms", false), "min": ("s", false), "hr": ("min", false),
        "day": ("hr", false), "week": ("day", false),
        // Area
        "mm²": ("in2", false), "cm²": ("in2", false), "m²": ("ft2", false), "km²": ("mi2", false),
        "in²": ("cm2", false), "ft²": ("m2", false), "yd²": ("m2", false), "mi²": ("km2", false),
        "acre": ("m2", false), "ha": ("acre", false),
        // Volume
        "mL": ("floz", false), "L": ("gal", false), "cup": ("ml", false), "tbsp": ("ml", false),
        "tsp": ("ml", false), "gal": ("l", false), "qt": ("l", false), "pt": ("ml", false),
        "fl oz": ("ml", false),
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
        // Data transfer rate
        "Mbps": ("kbps", false), "Gbps": ("mbps", false), "Kbps": ("bps", false),
    ]

    /// Lookup by lowercased, `²`-folded name (the tokenizer's ident form).
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
        add(UnitDef("m", "Meters", .length, 1), ["m", "meter", "meters", "metre", "metres"])
        add(
            UnitDef("km", "Kilometers", .length, 1000),
            ["km", "kilometer", "kilometers", "kilometre", "kilometres"])
        add(UnitDef("in", "Inches", .length, 0.0254), ["in", "inch", "inches"])
        add(UnitDef("ft", "Feet", .length, 0.3048), ["ft", "foot", "feet"])
        add(UnitDef("yd", "Yards", .length, 0.9144), ["yd", "yard", "yards"])
        add(UnitDef("mi", "Miles", .length, 1609.344), ["mi", "mile", "miles"])

        // Weight (base: kilogram)
        add(UnitDef("mg", "Milligrams", .weight, 1e-6), ["mg", "milligram", "milligrams"])
        add(UnitDef("g", "Grams", .weight, 0.001), ["g", "gram", "grams"])
        add(
            UnitDef("kg", "Kilograms", .weight, 1),
            ["kg", "kilogram", "kilograms", "kilo", "kilos"])
        add(UnitDef("oz", "Ounces", .weight, 0.028349523125), ["oz", "ounce", "ounces"])
        add(UnitDef("lb", "Pounds", .weight, 0.45359237), ["lb", "lbs", "pound", "pounds"])

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

        // Area (base: square meter). The tokenizer folds "²" to "2", so mm²/mm2 are one name.
        add(UnitDef("mm²", "Square Millimeters", .area, 1e-6), ["mm2", "sqmm"])
        add(UnitDef("cm²", "Square Centimeters", .area, 1e-4), ["cm2", "sqcm"])
        add(UnitDef("m²", "Square Meters", .area, 1), ["m2", "sqm"])
        add(UnitDef("km²", "Square Kilometers", .area, 1e6), ["km2", "sqkm"])
        add(UnitDef("in²", "Square Inches", .area, 0.00064516), ["in2", "sqin"])
        add(UnitDef("ft²", "Square Feet", .area, 0.09290304), ["ft2", "sqft"])
        add(UnitDef("yd²", "Square Yards", .area, 0.83612736), ["yd2", "sqyd"])
        add(UnitDef("mi²", "Square Miles", .area, 2_589_988.110336), ["mi2", "sqmi"])
        add(UnitDef("acre", "Acres", .area, 4046.8564224), ["acre", "acres"])
        add(UnitDef("ha", "Hectares", .area, 10000), ["ha", "hectare", "hectares"])

        // Volume (base: liter; US customary)
        add(
            UnitDef("mL", "Milliliters", .volume, 0.001),
            ["ml", "milliliter", "milliliters", "millilitre", "millilitres"])
        add(UnitDef("L", "Liters", .volume, 1), ["l", "liter", "liters", "litre", "litres"])
        add(UnitDef("cup", "Cups", .volume, 0.2365882365), ["cup", "cups"])
        add(
            UnitDef("tbsp", "Tablespoons", .volume, 0.01478676478125),
            ["tbsp", "tablespoon", "tablespoons"])
        add(
            UnitDef("tsp", "Teaspoons", .volume, 0.00492892159375),
            ["tsp", "teaspoon", "teaspoons"])
        add(UnitDef("gal", "Gallons", .volume, 3.785411784), ["gal", "gallon", "gallons"])
        add(UnitDef("qt", "Quarts", .volume, 0.946352946), ["qt", "quart", "quarts"])
        add(UnitDef("pt", "Pints", .volume, 0.473176473), ["pt", "pint", "pints"])
        add(UnitDef("fl oz", "Fluid Ounces", .volume, 0.0295735295625), ["floz"])

        // Digital storage (base: byte) — kB/MB/… are SI (1000ⁿ), KiB/MiB/… are IEC (1024ⁿ).
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

        // Angle (base: radian) — `deg` is also a trig postfix in CalcParser; the conversion path only fires for a standalone `<n> deg`.
        add(UnitDef("rad", "Radians", .angle, 1), ["rad", "radian", "radians"])
        add(UnitDef("deg", "Degrees", .angle, .pi / 180), ["deg", "degree", "degrees"])
        add(UnitDef("grad", "Gradians", .angle, .pi / 200), ["grad", "grads", "gradian", "gradians", "gon"])
        add(UnitDef("arcmin", "Arcminutes", .angle, .pi / 10800), ["arcmin", "arcminute", "arcminutes"])
        add(UnitDef("arcsec", "Arcseconds", .angle, .pi / 648000), ["arcsec", "arcsecond", "arcseconds"])
        add(UnitDef("turn", "Turns", .angle, 2 * .pi), ["turn", "turns", "rev", "revolution", "revolutions"])

        // Speed (base: meter/second) — slash-free aliases; symbols keep the pretty "/".
        add(UnitDef("m/s", "Meters per Second", .speed, 1), ["mps"])
        add(UnitDef("km/h", "Kilometers per Hour", .speed, 1000.0 / 3600), ["kmh", "kph"])
        add(UnitDef("mph", "Miles per Hour", .speed, 1609.344 / 3600), ["mph"])
        add(UnitDef("ft/s", "Feet per Second", .speed, 0.3048), ["fps"])
        add(UnitDef("kn", "Knots", .speed, 1852.0 / 3600), ["kn", "knot", "knots"])

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

        // Data transfer rate (base: bit/second) — SI (1000ⁿ) bit rates.
        add(UnitDef("bps", "Bits per Second", .dataRate, 1), ["bps"])
        add(UnitDef("Kbps", "Kilobits per Second", .dataRate, 1e3), ["kbps"])
        add(UnitDef("Mbps", "Megabits per Second", .dataRate, 1e6), ["mbps"])
        add(UnitDef("Gbps", "Gigabits per Second", .dataRate, 1e9), ["gbps"])
        add(UnitDef("Tbps", "Terabits per Second", .dataRate, 1e12), ["tbps"])

        return table
    }()
}
