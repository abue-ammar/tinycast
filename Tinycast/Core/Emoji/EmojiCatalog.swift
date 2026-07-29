import Foundation

/// Grid sections in display order; raw values are the compact codes used by the generated dataset.
enum EmojiCategory: String, CaseIterable, Sendable {
    case smileysAndPeople = "sp"
    case animalsAndNature = "an"
    case foodAndDrink = "fd"
    case activity = "ac"
    case travelAndPlaces = "tp"
    case objects = "ob"
    case symbols = "sy"
    case flags = "fl"
    case arrows = "xa"
    case currency = "xc"
    case math = "xm"
    case shapesAndPunctuation = "xs"

    var title: String {
        switch self {
        case .smileysAndPeople: return String(localized: "Smileys & People")
        case .animalsAndNature: return String(localized: "Animals & Nature")
        case .foodAndDrink: return String(localized: "Food & Drink")
        case .activity: return String(localized: "Activity")
        case .travelAndPlaces: return String(localized: "Travel & Places")
        case .objects: return String(localized: "Objects")
        case .symbols: return String(localized: "Symbols")
        case .flags: return String(localized: "Flags")
        case .arrows: return String(localized: "Arrows")
        case .currency: return String(localized: "Currency")
        case .math: return String(localized: "Math")
        case .shapesAndPunctuation: return String(localized: "Shapes & Punctuation")
        }
    }
}

/// Fitzpatrick skin tone preference; `modifier` is the scalar appended to tone-capable emoji.
enum EmojiSkinTone: String, CaseIterable, Identifiable, Sendable {
    case none, light, mediumLight, medium, mediumDark, dark

    var id: String { rawValue }

    var modifier: Unicode.Scalar? {
        switch self {
        case .none: return nil
        case .light: return Unicode.Scalar(0x1F3FB)
        case .mediumLight: return Unicode.Scalar(0x1F3FC)
        case .medium: return Unicode.Scalar(0x1F3FD)
        case .mediumDark: return Unicode.Scalar(0x1F3FE)
        case .dark: return Unicode.Scalar(0x1F3FF)
        }
    }

    var title: String {
        switch self {
        case .none: return String(localized: "Default")
        case .light: return String(localized: "Light")
        case .mediumLight: return String(localized: "Medium Light")
        case .medium: return String(localized: "Medium")
        case .mediumDark: return String(localized: "Medium Dark")
        case .dark: return String(localized: "Dark")
        }
    }

    /// Picker swatch: a waving hand rendered in this tone.
    var sample: String { EmojiCatalog.applyTone(self, to: "👋") }
}

/// One emoji or text symbol from the generated dataset; `glyph` is the base (untoned) form and doubles as the ID.
struct EmojiEntry: Identifiable, Hashable, Sendable {
    let glyph: String
    let name: String
    let category: EmojiCategory
    let supportsSkinTone: Bool
    let keywords: String  // space-joined search terms; empty for most symbols

    var id: String { glyph }
    var displayName: String { name.capitalized }

    func display(tone: EmojiSkinTone) -> String {
        guard supportsSkinTone, tone != .none else { return glyph }
        return EmojiCatalog.applyTone(tone, to: glyph)
    }
}

enum EmojiCatalog {
    /// Base scalar + tone modifier; VS16 is stripped because the modifier already forces emoji presentation (UTS #51).
    static func applyTone(_ tone: EmojiSkinTone, to glyph: String) -> String {
        guard let modifier = tone.modifier else { return glyph }
        var scalars = String.UnicodeScalarView(glyph.unicodeScalars.filter { $0.value != 0xFE0F })
        scalars.append(modifier)
        return String(scalars)
    }

    /// Parse the generated `glyph|name|category|tone|keywords` records; malformed lines are dropped.
    nonisolated static func parse(_ raw: String) -> [EmojiEntry] {
        var result: [EmojiEntry] = []
        result.reserveCapacity(2200)
        for line in raw.split(separator: "\n") {
            let fields = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5, let category = EmojiCategory(rawValue: String(fields[2]))
            else { continue }
            result.append(
                EmojiEntry(
                    glyph: String(fields[0]), name: String(fields[1]), category: category,
                    supportsSkinTone: fields[3] == "1", keywords: String(fields[4])))
        }
        return result
    }
}
