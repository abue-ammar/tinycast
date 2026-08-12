import AppKit

/// One browsable group of symbols. `id` is the CoreGlyphs category key, except for the two synthetic
/// ones the picker opens on.
struct SymbolCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String

    static let suggested = SymbolCategory(id: "tinycast.suggested", title: "Suggested")
    static let all = SymbolCategory(id: "tinycast.all", title: "All Symbols")
}

/// Every SF Symbol this macOS ships, read from the system at runtime rather than bundled: the list then
/// matches the OS exactly, with no data file to regenerate each release.
///
/// The source is `CoreGlyphs.bundle`, which carries the symbol order, each symbol's categories, and the
/// extra search terms the SF Symbols app searches on ("coffee" → `cup.and.saucer`). It's a system
/// resource, not API, so every read is optional and the curated list stands in if the layout ever
/// changes.
struct SymbolCatalog: Sendable {
    let symbols: [String]
    let categories: [SymbolCategory]

    private let byCategory: [String: [String]]
    private let searchTerms: [String: [String]]

    /// What the picker opens on — a short, hand-picked set, because scrolling eight thousand icons is
    /// not a way to choose one.
    static let suggested = [
        // Status & power
        "bolt.fill", "cup.and.saucer.fill", "moon.fill", "sun.max.fill", "power", "battery.100",
        "eye.fill", "bell.fill", "sparkles", "wand.and.stars",
        // Time
        "calendar", "clock.fill", "timer", "hourglass", "alarm.fill",
        // Text & documents
        "doc.text.fill", "text.alignleft", "checklist", "list.bullet", "note.text",
        "folder.fill", "tray.full.fill", "archivebox.fill", "book.fill", "bookmark.fill",
        // Communication
        "envelope.fill", "message.fill", "paperplane.fill", "phone.fill", "video.fill",
        "person.2.fill", "bubble.left.and.bubble.right.fill",
        // Media
        "music.note", "speaker.wave.2.fill", "headphones", "photo.fill", "camera.fill",
        "play.fill", "pause.fill", "paintbrush.fill", "theatermasks.fill",
        // Developer
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "hammer.fill",
        "wrench.and.screwdriver.fill", "ant.fill", "cpu", "memorychip", "externaldrive.fill",
        "server.rack", "shippingbox.fill",
        // System & network
        "gearshape.fill", "slider.horizontal.3", "network", "globe", "link", "wifi",
        "display", "keyboard", "cursorarrow.rays", "square.grid.2x2.fill",
        // Security & money
        "lock.fill", "key.fill", "shield.fill", "creditcard.fill", "cart.fill", "banknote.fill",
        // Data
        "chart.bar.fill", "chart.pie.fill", "function", "number", "brain",
        // Places & things
        "star.fill", "heart.fill", "flag.fill", "tag.fill", "map.fill", "location.fill",
        "airplane", "car.fill", "leaf.fill", "flame.fill", "drop.fill", "snowflake",
        "cloud.fill", "gift.fill", "trash.fill", "arrow.triangle.2.circlepath"
    ]

    /// The catalog with nothing but the curated set — what a missing or restructured CoreGlyphs falls
    /// back to, and what the picker shows until the real load finishes.
    static let fallback = SymbolCatalog(
        symbols: suggested.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil },
        categories: [.suggested],
        byCategory: [:],
        searchTerms: [:])

    /// Reads and filters the system catalog. Off the main actor: it parses ~700 KB of plists.
    nonisolated static func load() -> SymbolCatalog {
        let base = URL(
            fileURLWithPath:
                "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")

        func plist<T>(_ name: String, as type: T.Type) -> T? {
            guard let data = try? Data(contentsOf: base.appendingPathComponent(name)),
                let value = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil)
            else { return nil }
            return value as? T
        }

        guard let order = plist("symbol_order.plist", as: [String].self), !order.isEmpty else {
            return fallback
        }
        // Apple reserves ~600 symbols for its own products (iCloud, iPhone, AirPlay…) — using one to
        // label an extension would misuse their marks, so they're not offered.
        let restricted = Set(
            (plist("symbol_restrictions.strings", as: [String: String].self) ?? [:]).keys)
        let categoriesBySymbol = plist("symbol_categories.plist", as: [String: [String]].self) ?? [:]
        let search = plist("symbol_search.plist", as: [String: [String]].self) ?? [:]

        let symbols = order.filter { !restricted.contains($0) && !isLocaleVariant($0) }
        guard !symbols.isEmpty else { return fallback }

        var byCategory: [String: [String]] = [:]
        for symbol in symbols {
            for category in categoriesBySymbol[symbol] ?? [] where categoryTitles[category] != nil {
                byCategory[category, default: []].append(symbol)
            }
        }
        // Present categories in Apple's own order, skipping the ones that describe a rendering mode
        // (multicolor, variable…) rather than a subject.
        let ordered = (plist("categories.plist", as: [[String: String]].self) ?? [])
            .compactMap { $0["key"] }
            .filter { byCategory[$0]?.isEmpty == false }
            .compactMap { key in categoryTitles[key].map { SymbolCategory(id: key, title: $0) } }

        return SymbolCatalog(
            symbols: symbols,
            categories: [.suggested, .all] + ordered,
            byCategory: byCategory,
            searchTerms: search)
    }

    func symbols(in category: SymbolCategory) -> [String] {
        switch category.id {
        case SymbolCategory.suggested.id: return Self.suggested
        case SymbolCategory.all.id: return symbols
        default: return byCategory[category.id] ?? []
        }
    }

    /// Every query word has to hit the name (dots read as spaces) or one of the symbol's own search
    /// terms, so "coffee" finds `cup.and.saucer` and "arrow up" doesn't drown in every arrow.
    func search(_ query: String, in category: SymbolCategory) -> [String] {
        let words = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "." })
        guard !words.isEmpty else { return symbols(in: category) }
        // A search is a search: it looks through everything unless the user narrowed to a category.
        let pool = category.id == SymbolCategory.suggested.id ? symbols : symbols(in: category)
        return pool.filter { symbol in
            let haystack = symbol.replacingOccurrences(of: ".", with: " ")
            return words.allSatisfy { word in
                haystack.contains(word)
                    || (searchTerms[symbol] ?? []).contains { $0.lowercased().contains(word) }
            }
        }
    }

    /// Locale-specific renderings of a symbol that already exists (`.ar`, `.hi`, `.rtl`…) — a thousand
    /// near-duplicates that only add noise to a picker.
    private nonisolated static func isLocaleVariant(_ symbol: String) -> Bool {
        let suffixes: Set<String> = [
            "ar", "he", "hi", "ja", "ko", "th", "zh", "my", "km", "mn", "ne", "si", "ta", "te",
            "kn", "ml", "gu", "pa", "or", "bn", "ur", "am", "el", "ru", "sr", "rtl", "ltr"
        ]
        return symbol.split(separator: ".").contains { suffixes.contains(String($0)) }
    }

    /// Readable names for the CoreGlyphs category keys; anything absent here is a rendering-mode bucket
    /// (all / whatsnew / variable / multicolor / draw) and isn't browsable as a subject.
    private nonisolated static let categoryTitles: [String: String] = [
        "communication": "Communication", "weather": "Weather", "maps": "Maps",
        "objectsandtools": "Objects & Tools", "devices": "Devices",
        "cameraandphotos": "Camera & Photos", "gaming": "Gaming",
        "connectivity": "Connectivity", "transportation": "Transportation",
        "automotive": "Automotive", "accessibility": "Accessibility",
        "privacyandsecurity": "Privacy & Security", "human": "People", "home": "Home",
        "fitness": "Fitness", "nature": "Nature", "editing": "Editing",
        "textformatting": "Text Formatting", "media": "Media", "keyboard": "Keyboard",
        "commerce": "Commerce", "time": "Time", "health": "Health", "shapes": "Shapes",
        "arrows": "Arrows", "indices": "Indices", "math": "Math"
    ]
}
