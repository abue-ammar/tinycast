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
    case cjk = "xj"
    case keysAndTechnical = "xk"

    var title: String {
        switch self {
        case .smileysAndPeople: return "Smileys & People"
        case .animalsAndNature: return "Animals & Nature"
        case .foodAndDrink: return "Food & Drink"
        case .activity: return "Activity"
        case .travelAndPlaces: return "Travel & Places"
        case .objects: return "Objects"
        case .symbols: return "Symbols"
        case .flags: return "Flags"
        case .arrows: return "Arrows"
        case .currency: return "Currency"
        case .math: return "Math"
        case .shapesAndPunctuation: return "Shapes & Punctuation"
        case .cjk: return "CJK Symbols"
        case .keysAndTechnical: return "Keys & Technical"
        }
    }

    var systemImage: String {
        switch self {
        case .smileysAndPeople: "face.smiling"
        case .animalsAndNature: "pawprint"
        case .foodAndDrink: "pizza.slice"
        case .activity: "gamecontroller"
        case .travelAndPlaces: "paperplane"
        case .objects: "lightbulb"
        case .symbols: "number.sign"
        case .flags: "flag"
        case .arrows: "arrow.up.right"
        case .currency: "dollarsign"
        case .math: "squareroot"
        case .shapesAndPunctuation: "triangle"
        case .cjk: "globe"
        case .keysAndTechnical: "command"
        }
    }

    /// Names the selected character in Actions; Unicode's latter categories are symbol collections.
    var itemTitle: String {
        switch self {
        case .symbols, .arrows, .currency, .math, .shapesAndPunctuation, .cjk,
            .keysAndTechnical:
            "Symbol"
        default:
            "Emoji"
        }
    }
}

/// Which section the picker shows; `.all` keeps the catalog's complete ordered overview.
enum EmojiCategoryFilter: Hashable, Sendable {
    case all
    case pinned
    case frequentlyUsed
    case category(EmojiCategory)

    static let allCases: [Self] =
        [.all, .pinned, .frequentlyUsed] + EmojiCategory.allCases.map(Self.category)

    var title: String {
        switch self {
        case .all: "All Categories"
        case .pinned: "Pinned"
        case .frequentlyUsed: "Frequently Used"
        case .category(let category): category.title
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.3x3.square"
        case .pinned: "pin"
        case .frequentlyUsed: "clock"
        case .category(let category): category.systemImage
        }
    }
}

/// ⌘0 / ⌘+ / ⌘-: zooming in shows fewer, larger cells.
enum EmojiGridZoom: Sendable {
    case actualSize
    case zoomIn
    case zoomOut
}

/// User-selectable grid density. Zoom changes this for the current picker session only.
enum EmojiGridColumns: Int, CaseIterable, Identifiable, Sendable {
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10

    static let `default`: Self = .eight

    var id: Int { rawValue }
    var title: String { "\(rawValue) columns" }

    /// Nil when the zoom would change nothing: already at the default, or at six or ten columns.
    func applying(_ zoom: EmojiGridZoom, default defaultColumns: Self) -> Self? {
        let next: Self? =
            switch zoom {
            case .actualSize: defaultColumns
            case .zoomIn: Self(rawValue: rawValue - 1)
            case .zoomOut: Self(rawValue: rawValue + 1)
            }
        return next == self ? nil : next
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
        case .none: return "Default"
        case .light: return "Light"
        case .mediumLight: return "Medium Light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium Dark"
        case .dark: return "Dark"
        }
    }

    var sample: String { EmojiCatalog.applyTone(self, to: "👋") }
}

/// One emoji or symbol; `glyph` is the base (untoned) form and doubles as the ID.
struct EmojiEntry: Identifiable, Hashable, Sendable {
    let glyph: String
    let name: String
    let category: EmojiCategory
    let supportsSkinTone: Bool
    let keywords: String  // comma-joined search terms; empty for most symbols

    var id: String { glyph }
    var displayName: String { name.capitalized }

    func display(tone: EmojiSkinTone) -> String {
        guard supportsSkinTone, tone != .none else { return glyph }
        return EmojiCatalog.applyTone(tone, to: glyph)
    }
}

enum EmojiCatalog {
    /// Base scalar + tone modifier; VS16 is stripped, the modifier already forcing emoji (UTS #51).
    static func applyTone(_ tone: EmojiSkinTone, to glyph: String) -> String {
        guard let modifier = tone.modifier else { return glyph }
        var scalars = String.UnicodeScalarView(glyph.unicodeScalars.filter { $0.value != 0xFE0F })
        scalars.append(modifier)
        return String(scalars)
    }

    /// Parse the generated `glyph|name|category|tone|keywords` records, dropping malformed lines.
    nonisolated static func parse(_ raw: String, localized: [String] = []) -> [EmojiEntry] {
        let localizedTerms = terms(in: localized)
        var result: [EmojiEntry] = []
        result.reserveCapacity(2200)
        for line in raw.split(separator: "\n") {
            let fields = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5, let category = EmojiCategory(rawValue: String(fields[2]))
            else { continue }
            let glyph = String(fields[0])
            var keywords = String(fields[4])
            for pack in localizedTerms[glyph] ?? [] {
                if !keywords.isEmpty { keywords += "," }
                keywords += pack
            }
            result.append(
                EmojiEntry(
                    glyph: glyph, name: String(fields[1]), category: category,
                    supportsSkinTone: fields[3] == "1", keywords: keywords))
        }
        return result
    }

    private nonisolated static func terms(in packs: [String]) -> [String: [Substring]] {
        var result: [String: [Substring]] = [:]
        for pack in packs {
            for line in pack.split(separator: "\n") {
                let fields = line.split(separator: "|", maxSplits: 1)
                guard fields.count == 2 else { continue }
                result[String(fields[0]), default: []].append(fields[1])
            }
        }
        return result
    }

    /// A pack per language the Mac reads; "en" is the catalog and the matcher's answer to no match.
    nonisolated static func keywordLanguages(available: [String], preferred: [String]) -> [String] {
        let candidates = ["en"] + available
        var result: [String] = []
        for language in preferred {
            guard
                let match = Bundle.preferredLocalizations(
                    from: candidates, forPreferences: [language]
                ).first,
                match != "en", !result.contains(match)
            else { continue }
            result.append(match)
        }
        return result
    }
}
