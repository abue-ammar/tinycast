import AppKit

/// One group of symbols; `id` is the CoreGlyphs key, but for the two synthetic ones.
struct SymbolCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String

    static let suggested = SymbolCategory(id: "tinycast.suggested", title: "Suggested")
    static let all = SymbolCategory(id: "tinycast.all", title: "All Symbols")
    static let bundled = SymbolCategory(id: "tinycast.bundled", title: "Tinycast")
}

/// Read from `CoreGlyphs.bundle` at runtime, so the list matches the OS. A system resource, not API:
/// every read is optional and the curated list stands in if its layout ever changes.
struct SymbolCatalog: Sendable {
    let symbols: [String]
    let categories: [SymbolCategory]

    private let byCategory: [String: [String]]
    private let searchTerms: [String: [String]]

    /// Marks we ship ourselves: the system has no bluetooth symbol at all, restricted or otherwise.
    static let bundledGlyphs = ["bluetooth", "BrandGitHub", "BrandDiscord", "BrandX"]

    static func isBundled(_ symbol: String) -> Bool { bundledGlyphs.contains(symbol) }

    /// Search terms for the app's own marks, since they carry none of CoreGlyphs' metadata.
    private nonisolated static let bundledTerms: [String: [String]] = [
        "bluetooth": ["bluetooth", "wireless", "pair", "device"],
        "BrandGitHub": ["github", "git", "repository", "code", "brand"],
        "BrandDiscord": ["discord", "chat", "community", "brand"],
        "BrandX": ["x", "twitter", "social", "brand"]
    ]

    /// What the picker opens on: scrolling eight thousand icons is not a way to choose one.
    static let suggested =
        bundledGlyphs + [
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

    /// The curated set alone: the fallback, and what the picker shows until the real load lands.
    static let fallback = SymbolCatalog(
        symbols: suggested.filter {
            isBundled($0) || NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        },
        categories: [.suggested, .bundled],
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
        // Apple reserves ~600 for its own products; labelling an extension with one misuses the mark.
        let restricted = Set(
            (plist("symbol_restrictions.strings", as: [String: String].self) ?? [:]).keys)
        let categoriesBySymbol = plist("symbol_categories.plist", as: [String: [String]].self) ?? [:]
        let search = plist("symbol_search.plist", as: [String: [String]].self) ?? [:]

        let systemSymbols = order.filter { !restricted.contains($0) && !isLocaleVariant($0) }
        guard !systemSymbols.isEmpty else { return fallback }
        // The app's own marks lead, so what the system lacks is the first thing offered.
        let symbols = bundledGlyphs + systemSymbols

        var byCategory: [String: [String]] = [:]
        for symbol in symbols {
            for category in categoriesBySymbol[symbol] ?? [] where categoryTitles[category] != nil {
                byCategory[category, default: []].append(symbol)
            }
        }
        // Apple's own order, skipping buckets that describe a rendering mode rather than a subject.
        let ordered = (plist("categories.plist", as: [[String: String]].self) ?? [])
            .compactMap { $0["key"] }
            .filter { byCategory[$0]?.isEmpty == false }
            .compactMap { key in categoryTitles[key].map { SymbolCategory(id: key, title: $0) } }

        return SymbolCatalog(
            symbols: symbols,
            categories: [.suggested, .bundled, .all] + ordered,
            byCategory: byCategory,
            searchTerms: search.merging(bundledTerms) { system, _ in system })
    }

    func symbols(in category: SymbolCategory) -> [String] {
        switch category.id {
        case SymbolCategory.suggested.id: return Self.suggested
        case SymbolCategory.bundled.id: return Self.bundledGlyphs
        case SymbolCategory.all.id: return symbols
        default: return byCategory[category.id] ?? []
        }
    }

    /// Every word must hit the name or a search term, so "coffee" finds `cup.and.saucer`.
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

    /// Locale renderings of symbols that already exist: a thousand near-duplicates, all noise here.
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
