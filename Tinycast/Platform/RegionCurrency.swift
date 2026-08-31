import Foundation

/// A Language & Region read, never CoreLocation, so nothing is prompted.
enum RegionCurrency {
    static var code: String? { Locale.current.currency?.identifier }
}
