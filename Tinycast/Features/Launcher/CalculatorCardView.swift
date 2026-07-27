import SwiftUI

/// One-deep memo over `CalcEngine.evaluate`, mirroring `AppIndex.matchCache`, so hover/selection
/// re-renders with the same query don't re-run the evaluator. Keyed on the consent flag plus the
/// snapshot's `fetchedAt`, so flipping the setting or landing a fresh table invalidates the memo
/// without comparing the rate table itself.
@MainActor
enum CalcMemo {
    private static var cache: (query: String, enabled: Bool, stamp: Date?, result: CalcResult?)?

    static func evaluate(_ query: String, currency: CurrencySource) -> CalcResult? {
        let enabled: Bool
        let stamp: Date?
        switch currency {
        case .off:
            enabled = false
            stamp = nil
        case .on(let rates):
            enabled = true
            stamp = rates?.fetchedAt
        }
        if let cache, cache.query == query, cache.enabled == enabled, cache.stamp == stamp {
            return cache.result
        }
        let result = CalcEngine.evaluate(query, currency: currency)
        cache = (query, enabled, stamp, result)
        return result
    }
}

/// The inline answer card pinned above the app results (expression → result, or a friendly message on impossible conversion); selectable like a row, Enter copies.
struct CalculatorCard: View {
    let result: CalcResult
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        Group {
            switch result.payload {
            case .value(let display, _):
                HStack(spacing: 0) {
                    CalcColumn(text: result.expression, badge: result.sourceBadge, weight: .medium)
                    Image(systemName: "arrow.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    CalcColumn(text: display, badge: result.targetBadge, weight: .semibold)
                }
                .fixedSize(horizontal: false, vertical: true)
            case .error(let message):
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                    Text(message)
                        .lineLimit(1)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xxxl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// One side of the two-column answer card: the value line with an optional word-name badge pill beneath ("Meters", "9:00 AM").
private struct CalcColumn: View {
    let text: String
    let badge: String?
    let weight: Font.Weight

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(text)
                .font(Theme.Typography.calcResult.weight(weight))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let badge {
                Text(badge)
                    .font(Theme.Typography.keyCap)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                            .fill(Theme.Colors.controlSurface)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

/// Actions menu content for the calculator card — only answers can be copied, so an error card gets no menu (the caller passes `calc` only for value payloads).
@MainActor
enum CalcActionsMenu {
    static func content(result: CalcResult, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: result.expression,
            items: [
                PopoverMenuItem(title: "Copy Answer", systemImage: "doc.on.doc", shortcut: "↵") {
                    core.copyCalculatorResult(result)
                }
            ]
        )
    }
}
