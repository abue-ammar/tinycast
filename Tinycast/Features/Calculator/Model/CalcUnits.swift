import Foundation

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
        } else if let value = CalcExpressionParser.scalar(valueTokens) {
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
        guard let input = CalcExpressionParser.scalar(valueTokens) else { return nil }

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

    static let byName = CalcUnitCatalog.makeIndex()
}
