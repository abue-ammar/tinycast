import Foundation

/// Cooking ingredients between weight and volume: `1 cup of flour in grams`, `density of honey`.
enum CalcSubstance {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.contains(where: isIngredientWord) else { return nil }
        return density(tokens, query: query) ?? converted(tokens, query: query)
    }

    /// Grams per US cup, from USDA FoodData Central's household measures; the only curated data here.
    private static let gramsPerCup: [String: Double] = [
        "water": 236.5882365, "milk": 244, "buttermilk": 245, "heavy cream": 238, "cream": 238,
        "sour cream": 230, "yogurt": 245, "yoghurt": 245, "cream cheese": 232,
        "flour": 125, "all purpose flour": 125, "bread flour": 137, "whole wheat flour": 120,
        "sugar": 200, "granulated sugar": 200, "white sugar": 200, "brown sugar": 220, "powdered sugar": 120,
        "icing sugar": 120, "butter": 227, "honey": 339, "maple syrup": 315, "molasses": 337,
        "corn syrup": 328,
        "oil": 218, "vegetable oil": 218, "olive oil": 216, "coconut oil": 218, "shortening": 205,
        "lard": 205,
        "salt": 292, "baking soda": 220.8, "baking powder": 220.8, "cocoa": 86, "cocoa powder": 86,
        "cornstarch": 128, "oats": 81, "rolled oats": 81, "rice": 185, "white rice": 185, "brown rice": 190,
        "quinoa": 170, "lentils": 192, "peanut butter": 258, "chocolate chips": 168, "raisins": 145,
        "almonds": 143, "walnuts": 117, "shredded cheese": 113, "parmesan": 100, "mayonnaise": 220,
        "ketchup": 240
    ]

    private static let cupMilliliters = 236.5882365

    private static let words: Set<String> = Set(
        gramsPerCup.keys.flatMap { $0.split(separator: " ").map(String.init) })

    private static func isIngredientWord(_ token: CalcToken) -> Bool {
        guard case .ident(let name) = token else { return false }
        return words.contains(name)
    }

    /// The ingredient that `tokens` ends with, longest name first, and where it starts.
    private static func ingredient(endingAt tokens: ArraySlice<CalcToken>) -> (name: String, start: Int)? {
        for length in stride(from: min(3, tokens.count), through: 1, by: -1) {
            let start = tokens.endIndex - length
            let names = tokens[start...].compactMap { token -> String? in
                guard case .ident(let name) = token else { return nil }
                return name
            }
            let name = names.joined(separator: " ")
            if names.count == length, gramsPerCup[name] != nil { return (name, start) }
        }
        return nil
    }

    // MARK: - Density

    private static func density(_ tokens: [CalcToken], query: String) -> CalcResult? {
        let name: String
        if tokens.first == .ident("density"), tokens.count > 2, tokens[1] == .ident("of"),
            let found = ingredient(endingAt: tokens[2...]), found.start == 2
        {
            name = found.name
        } else if tokens.last == .ident("density"), let found = ingredient(endingAt: tokens.dropLast()),
            found.start == 0
        {
            name = found.name
        } else {
            return nil
        }
        guard let grams = gramsPerCup[name] else { return nil }
        let text = CalcFormatter.display(grams / cupMilliliters) + " g/cm³"
        return CalcResult(
            expression: query, sourceBadge: name.capitalized, targetBadge: String(localized: "Density"),
            payload: .value(display: text, copyText: text), canChain: false)
    }

    // MARK: - Weight and volume

    /// `1 cup of flour in grams`, `200 g butter in cups`: the ingredient sits between amount and target.
    private static func converted(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 4, case .ident(let targetName) = tokens.last,
            CalcUnits.isConnector(tokens[tokens.count - 2]),
            let target = CalcUnits.byName[targetName] ?? CalcUnits.byName[targetName.lowercased()],
            let found = ingredient(endingAt: tokens[..<(tokens.count - 2)]),
            let grams = gramsPerCup[found.name]
        else { return nil }
        var amountTokens = Array(tokens[..<found.start])
        if amountTokens.last == .ident("of") { amountTokens.removeLast() }
        guard let amount = CalcExpressionParser.value(amountTokens), case .unit(let source) = amount.kind
        else { return nil }
        let gramsPerMilliliter = grams / cupMilliliters
        let output: Double
        switch (source.category, target.category) {
        case (.volume, .weight):
            let milliliters = amount.amount * source.factor * 1e6
            output = milliliters * gramsPerMilliliter / 1000 / target.factor
        case (.weight, .volume):
            let milliliters = amount.amount * source.factor * 1000 / gramsPerMilliliter
            output = milliliters / 1e6 / target.factor
        case (.volume, .volume), (.weight, .weight):
            output = CalcQuantity.convertUnit(amount.amount, from: source, to: target)
        default:
            return nil
        }
        guard output.isFinite else { return nil }
        return CalcResult(
            expression: "\(CalcFormatter.display(amount.amount)) \(source.symbol) \(found.name)",
            sourceBadge: found.name.capitalized, targetBadge: target.name,
            payload: .measurement(output, unit: target))
    }
}
