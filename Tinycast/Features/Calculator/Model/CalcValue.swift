import Foundation

struct CalcValue {
    enum Kind {
        case scalar
        case unit(UnitDef)
        case currency(CurrencyDef)
    }

    var amount: Double
    var kind: Kind
    var isPercent = false
    var isBoolean = false
    /// `24.5 l / 350 km` lands on area's dimension, so only the division knows it was fuel.
    var isFuelRatio = false

    var effective: Double {
        isPercent ? amount / 100 : amount
    }
}
