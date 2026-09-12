import Foundation

enum CalcToken: Equatable, Sendable {
    case number(Double)
    /// Shorthand (`10k`, `1e5`), kept distinct so a lone one still earns a card.
    case compactNumber(Double)
    /// Radix-prefixed integer literal (0xff / 0b1010 / 0o777), kept exact for base conversion.
    case intLiteral(UInt64, base: CalcNumberBase)
    case ident(String)
    case op(CalcOperator)
    case arrow  // -> or →
    case comma
}
