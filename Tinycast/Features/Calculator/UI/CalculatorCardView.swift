import SwiftUI

/// One-deep memo over `CalcEngine.evaluate`, keyed on the rate snapshot's `fetchedAt`.
@MainActor
enum CalcMemo {
    private struct Cache {
        let query: String
        let stamp: Date?
        let region: String?
        let result: CalcResult?
    }

    private static var cache: Cache?

    static func evaluate(_ query: String, rates: CurrencyRates?) -> CalcResult? {
        let region = RegionCurrency.code
        if let cache, cache.query == query, cache.stamp == rates?.fetchedAt, cache.region == region {
            return cache.result
        }
        let result = CalcEngine.evaluate(query, rates: rates, region: region)
        cache = Cache(query: query, stamp: rates?.fetchedAt, region: region, result: result)
        return result
    }
}

/// The inline answer card above the app results; selectable like a row, Enter copies.
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

/// One side of the answer card: a value line with an optional word-name badge pill beneath.
private struct CalcColumn: View {
    let text: String
    let badge: String?
    let weight: Font.Weight

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text(CalcSyntax.highlighted(text))
                .font(Theme.Typography.calcResult.weight(weight))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let badge {
                Text(badge)
                    .font(Theme.Typography.keyCap)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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

/// Dims the words that join an expression, so the values they join read first.
private enum CalcSyntax {
    static func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString()
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        // Rebuilt word by word, so a connector is only ever matched whole — `min` is not `in`.
        for (index, word) in words.enumerated() {
            if index > 0 { attributed.append(AttributedString(" ")) }
            var piece = AttributedString(String(word))
            if isConnector(word, at: index, of: words) {
                piece.foregroundColor = Theme.Colors.textTertiary
            }
            attributed.append(piece)
        }
        return attributed
    }

    /// `in` joins two units and follows one, which is what separates it from the inch it spells.
    /// In `10 in in cm` only the second joins, so the first stays a unit.
    private static func isConnector(
        _ word: Substring, at index: Int, of words: [Substring]
    ) -> Bool {
        let lowered = word.lowercased()
        if connectors.contains(lowered) { return true }
        guard lowered == "in", index > 0, index + 1 < words.count else { return false }
        return words[index + 1].lowercased() != "in"
    }

    /// Words only, never a unit: `min` and `in` are also units, so they are matched by position.
    private static let connectors: Set<String> = [
        "to", "of", "off", "on", "as", "from", "ago", "at", "tip", "ratio", "average", "avg",
        "mean", "sum", "total", "round", "nearest", "and", "is", "what", "the", "next", "last",
        "+", "-", "×", "÷", "^", "→", "->", "mod"
    ]
}

/// Actions menu for the card; only answers copy, so an error card is never passed one.
@MainActor
enum CalcActionsMenu {
    static func content(result: CalcResult, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: result.expression,
            items: [
                PopoverMenuItem(title: "Copy Answer", systemImage: "doc.on.doc", shortcut: "↵") {
                    core.calculatorCoordinator.copyCalculatorResult(result)
                }
            ]
        )
    }
}
