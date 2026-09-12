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

    var effective: Double {
        isPercent ? amount / 100 : amount
    }
}
