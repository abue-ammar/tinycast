import Foundation

/// The Mac's own currency — a Language & Region read, never CoreLocation, so nothing is prompted.
/// Unstored because `Locale.current` already re-resolves after the region preference changes.
enum RegionCurrency {
    static var code: String? { Locale.current.currency?.identifier }
}
