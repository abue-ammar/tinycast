import Foundation

/// Follows Language & Region's number format, so a change there applies without a relaunch.
@MainActor
@Observable
final class RegionNumberFormatMonitor {
    private(set) var system = RegionNumberFormatMonitor.read()
    @ObservationIgnored private var token: NotificationCenter.ObservationToken?

    init() {
        token = NotificationCenter.default.addObserver(of: Locale.self, for: .currentLocaleDidChange) {
            [weak self] _ in
            self?.system = Self.read()
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    func format(for style: CalcNumberStyle) -> CalcNumberFormat {
        style == .system ? system : .english
    }

    /// Separators the parser can't take, such as the Arabic `٫`, fall back to English.
    private static func read() -> CalcNumberFormat {
        let locale = Locale.autoupdatingCurrent
        let sizes = groupingSizes(of: locale)
        return CalcNumberFormat(
            decimalSeparator: locale.decimalSeparator ?? ".",
            groupingSeparator: locale.groupingSeparator, primaryGrouping: sizes.primary,
            secondaryGrouping: sizes.secondary) ?? .english
    }

    /// Only `NumberFormatter` publishes the region's group widths, such as India's 3 + 2.
    private static func groupingSizes(of locale: Locale) -> (primary: Int, secondary: Int?) {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        guard formatter.groupingSize > 0 else { return (3, nil) }
        return (formatter.groupingSize, formatter.secondaryGroupingSize)
    }
}
