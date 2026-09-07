import Foundation

/// A unit as an affine map onto its base: `base = value * factor + offset`. Temperature only.
final class UnitDef: Equatable, Sendable {
    let symbol: String  // canonical display form: "mi", "°F", "GiB"
    let name: String  // long label for the card badge: "Miles", "Fahrenheit"
    let category: UnitCategory
    let factor: Double
    let offset: Double
    let derivedDimension: CalcDimension?
    let currency: CurrencyDef?

    var dimension: CalcDimension? { derivedDimension ?? category.dimension }

    static func == (lhs: UnitDef, rhs: UnitDef) -> Bool {
        lhs === rhs
            || (lhs.symbol == rhs.symbol && lhs.name == rhs.name && lhs.category == rhs.category
                && lhs.factor == rhs.factor && lhs.offset == rhs.offset
                && lhs.derivedDimension == rhs.derivedDimension
                && lhs.currency == rhs.currency)
    }

    func isCompatible(with other: UnitDef) -> Bool {
        if category != .compound, category == other.category { return true }
        guard let dimension else { return false }
        return dimension == other.dimension
    }

    @inline(never) init(
        _ symbol: String, _ name: String, _ category: UnitCategory, _ factor: Double,
        offset: Double = 0, dimension: CalcDimension? = nil, currency: CurrencyDef? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.category = category
        self.factor = factor
        self.offset = offset
        derivedDimension = dimension
        self.currency = currency
    }
}
