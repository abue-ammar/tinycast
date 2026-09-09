import Foundation

@main
@MainActor
struct ClipboardSearchTests {
    static var checks = 0
    static var metadata: [UUID: String] = [:]
    static let queries = [
        "", " ", "a", "al", "common", "invoice", "rare", "absent-value",
        "COMMON", "café", "日本語", "say \"yes\"", "  common  ", "pdf"
    ]

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-search-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory)
        store.maxAge = ClipboardRetention.forever.maxAge
        let now = Date()
        let entries = (0..<2500).map { index in
            let kind: ClipboardItem.Kind = index % 3 == 0 ? .text : index % 3 == 1 ? .file : .image
            let suffix = " \(index) café 日本語 say \"yes\"" + (index % 401 == 0 ? " rare" : "")
            let item = ClipboardItem(
                id: UUID(), kind: kind,
                text: kind == .text
                    ? "Common alphabet" + suffix : kind == .file ? "/fixture/common\(index).pdf" : nil,
                imagePath: kind == .image ? "/fixture/\(index).png" : nil,
                createdAt: now.addingTimeInterval(Double(-index)), sourceBundleID: nil,
                pinnedAt: index < 220 ? now.addingTimeInterval(Double(-index)) : nil)
            if kind != .text, index % 7 != 0 { metadata[item.id] = "Common invoice" + suffix }
            return item
        }
        precondition(ClipboardStore.importStoredItems(inDatabaseAt: store.dbURL, entries) == entries.count)
        store.load()
        try await compare(store, phase: "disabled by default")
        precondition(store.setTextSearchEnabled(true))
        for entry in entries {
            if let text = metadata[entry.id] {
                precondition(store.setExtractedText(text, for: entry, generation: store.extractionGeneration))
            }
        }
        try await compare(store, phase: "enabled mixed history")
        let old = entries[224]
        metadata[old.id] = "common invoice rare"
        precondition(
            store.setExtractedText(metadata[old.id]!, for: old, generation: store.extractionGeneration))
        try await compare(store, phase: "late OCR outside window")
        store.promote(entries[400])
        store.togglePinned(entries[401])
        try await compare(store, phase: "promotion and pinning")
        store.setTextSearchEnabled(false)
        store.promote(entries[401])
        store.togglePinned(store.items.first { $0.id == entries[401].id }!)
        store.promote(entries[400])
        try await compare(store, phase: "disabled with populated OCR database")
        store.setTextSearchEnabled(true)
        try await compare(store, phase: "reenabled preserves historical text")
        store.remove(entries[400])
        metadata.removeValue(forKey: entries[400].id)
        try await compare(store, phase: "deleted indexed row")
        store.close()
        store.open()
        store.load()
        try await compare(store, phase: "reopened defaults off")
        store.setTextSearchEnabled(true)
        try await compare(store, phase: "reopened and enabled")
        _ = store.search("common", filter: .all)
        _ = store.search("common", filter: .image)
        _ = store.search("common", filter: .file)
        for _ in 0..<2000 {
            if store.search("common", filter: .file).contains(where: { metadata[$0.id] != nil }) { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        precondition(store.search("common", filter: .file).allSatisfy { $0.kind == .file })
        _ = store.search("", filter: .all)
        var publications: [String] = []
        store.onSearchResultsChanged = { query, _, _ in publications.append(query) }
        _ = store.search("invoice", filter: .all)
        _ = store.search("raretoken-never-present", filter: .all)
        store.setTextSearchActive(false)
        try await Task.sleep(for: .milliseconds(40))
        precondition(publications.isEmpty, "hidden palette accepts no superseded publications")
        precondition(
            store.search("invoice", filter: .all).isEmpty, "hidden palette cannot restart OCR search")
        store.setTextSearchActive(true)
        store.clearAll()
        metadata = [:]
        try await compare(store, phase: "cleared")
        store.close()
        for query in queries { precondition(store.search(query, filter: .all).isEmpty) }
        print("\(checks) search comparisons passed")
    }

    static func sameResults(_ actual: [ClipboardItem], _ expected: [ClipboardItem]) -> Bool {
        actual.map(\.id) == expected.map(\.id) && actual.map(\.isPinned) == expected.map(\.isPinned)
    }

    static func compare(_ store: ClipboardStore, phase: String) async throws {
        var stored: [ClipboardItem] = []
        ClipboardStore.forEachStoredItem(inDatabaseAt: store.dbURL) { stored.append($0) }
        let all = Array(stored.reversed())
        let pins = store.items.filter(\.isPinned).sorted { $0.pinnedAt! < $1.pinnedAt! }
        for query in queries {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            let candidates = trimmed.count < 3 ? store.items : all
            let normal =
                trimmed.isEmpty
                ? store.items.filter { !$0.isPinned }
                : Array(candidates.filter { $0.matches(trimmed) }.prefix(trimmed.count < 3 ? Int.max : 200))
                    .filter { !$0.isPinned }
            let normalPins = trimmed.isEmpty ? pins : pins.filter { $0.matches(trimmed) }
            for filter in ClipboardFilter.allCases {
                _ = store.search("", filter: .all)
                var completed = false
                store.onSearchResultsChanged = { _, _, _ in completed = true }
                let immediate = store.search(query, filter: filter)
                let expectedImmediate = filter.apply(to: normalPins + normal)
                precondition(
                    sameResults(immediate, expectedImmediate), "\(phase): immediate \(query) / \(filter)")
                var expected = expectedImmediate
                if store.textSearchEnabled, !trimmed.isEmpty,
                    filter == .all || filter == .image || filter == .file
                {
                    for _ in 0..<2000 {
                        if completed { break }
                        try await Task.sleep(for: .milliseconds(2))
                    }
                    precondition(completed, "query publication timed out")
                    let recognized = filter.apply(to: candidates).filter {
                        metadata[$0.id]?.localizedCaseInsensitiveContains(trimmed) == true
                    }
                    let allPins = pins.filter { pin in
                        pin.matches(trimmed) || recognized.contains { $0.id == pin.id }
                    }
                    let ordinaryIDs = Set(normal.map(\.id))
                    let extra = recognized.filter { !$0.isPinned }.prefix(200)
                        .filter { !ordinaryIDs.contains($0.id) }
                    expected = filter.apply(
                        to: allPins + normal + extra.prefix(max(0, 200 - filter.apply(to: normal).count)))
                }
                let actual = store.search(query, filter: filter)
                if store.textSearchEnabled, !metadata.isEmpty, trimmed == "common", filter == .image {
                    precondition(!actual.isEmpty, "ordinary text and OCR files cannot starve image matches")
                }
                precondition(sameResults(actual, expected), "\(phase): settled \(query) / \(filter)")
                precondition(sameResults(store.search(query, filter: filter), expected), "memo differs")
                precondition(Set(actual.map(\.id)).count == actual.count, "duplicate result")
                checks += 1
            }
        }
        store.onSearchResultsChanged = nil
    }
}
