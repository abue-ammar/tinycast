import Foundation
import Testing

@testable import Tinycast

@MainActor
struct ClipboardSearchTests {
    nonisolated private static let queries = [
        "", " ", "a", "al", "common", "invoice", "rare", "absent-value",
        "COMMON", "café", "日本語", "say \"yes\"", "  common  ", "pdf"
    ]

    @Test(.timeLimit(.minutes(2)), arguments: queries, ClipboardFilter.allCases)
    func searchKeepsOrdinaryAndRecognizedRowsInOrderAcrossHistoryChanges(
        _ query: String, _ filter: ClipboardFilter
    ) async throws {
        var history = try SearchHistory()
        let store = history.store
        let term = query.trimmingCharacters(in: .whitespaces)

        for stage in SearchHistory.Stage.allCases {
            try history.advance(to: stage)
            let expected = history.results(for: term, filter: filter)
            _ = store.search("", filter: .all)
            let immediate = store.search(query, filter: filter)
            #expect(immediate.map(ResultRow.init) == expected.immediate, "\(stage)")

            if expected.recognized != nil {
                let task = try #require(store.textSearchTask, "\(stage)")
                await confirmation("OCR published \(stage)") { published in
                    store.onSearchResultsChanged = { _, _, _ in published() }
                    await task.value
                    store.onSearchResultsChanged = nil
                }

                if !history.metadata.isEmpty, term == "common", filter == .image {
                    #expect(!store.search(query, filter: filter).isEmpty, "\(stage)")
                }
            }
            let settled = expected.recognized ?? expected.immediate
            let actual = store.search(query, filter: filter)
            #expect(actual.map(ResultRow.init) == settled, "\(stage)")
            #expect(store.search(query, filter: filter).map(ResultRow.init) == settled, "\(stage) memo")
            #expect(Set(actual.map(\.id)).count == actual.count, "\(stage)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func switchingFiltersWhileOCRIsPendingPublishesOnlyTheFinalFileRequest() async throws {
        let history = try SearchHistory(through: .enabledAfterReopen)
        let store = history.store

        try await confirmation { published in
            store.onSearchResultsChanged = { query, _, rows in
                published()
                #expect(query == "common")
                #expect(rows.allSatisfy { $0.kind == .file })
            }
            defer { store.onSearchResultsChanged = nil }
            _ = store.search("common", filter: .all)
            let all = try #require(store.textSearchTask)
            _ = store.search("common", filter: .image)
            let images = try #require(store.textSearchTask)
            _ = store.search("common", filter: .file)
            let files = try #require(store.textSearchTask)
            await all.value
            await images.value
            await files.value
        }

        #expect(store.search("common", filter: .file).allSatisfy { $0.kind == .file })
    }

    @Test(.timeLimit(.minutes(1)))
    func hidingCancelsPendingOCRPublicationAndPreventsNewOCRWork() async throws {
        let history = try SearchHistory(through: .enabledAfterReopen)
        let store = history.store

        try await confirmation(expectedCount: 0) { published in
            store.onSearchResultsChanged = { _, _, _ in published() }
            defer { store.onSearchResultsChanged = nil }
            _ = store.search("invoice", filter: .all)
            let superseded = try #require(store.textSearchTask)
            _ = store.search("raretoken-never-present", filter: .all)
            let pending = try #require(store.textSearchTask)
            store.setTextSearchActive(false)
            await superseded.value
            await pending.value

            #expect(store.search("invoice", filter: .all).isEmpty)
            #expect(store.textSearchTask == nil)
        }
    }

    @Test(arguments: queries)
    func closedHistoryReturnsNoResults(_ query: String) throws {
        let history = try SearchHistory(through: .cleared)
        history.store.close()
        #expect(history.store.search(query, filter: .all).isEmpty)
    }

    private struct ResultRow: Equatable {
        let id: UUID
        let isPinned: Bool

        init(_ item: ClipboardItem) {
            id = item.id
            isPinned = item.isPinned
        }
    }

    @MainActor
    private struct SearchHistory {
        enum Stage: CaseIterable {
            case initiallyDisabled, enabled, lateRecognition, promotedAndPinned, disabledWithMetadata
            case reenabled, rowDeleted, reopened, enabledAfterReopen, cleared
        }

        private let scratch: ScratchDirectory
        private let entries: [ClipboardItem]
        let store: ClipboardStore
        private(set) var metadata: [UUID: String] = [:]

        init() throws {
            scratch = try ScratchDirectory("clipboard-search")
            store = ClipboardStore(directory: scratch.url)
            store.maxAge = ClipboardRetention.forever.maxAge
            let now = Date()
            entries = (0..<2500).map { index in
                let kind: ClipboardItem.Kind =
                    switch index % 3 {
                    case 0: .text
                    case 1: .file
                    default: .image
                    }
                let text: String? =
                    switch kind {
                    case .text: "Common alphabet" + Self.suffix(at: index)
                    case .file: "/fixture/common\(index).pdf"
                    case .image: nil
                    }
                let date = now - Double(index)
                return ClipboardItem(
                    id: UUID(), kind: kind, text: text,
                    imagePath: kind == .image ? "/fixture/\(index).png" : nil,
                    createdAt: date, sourceBundleID: nil, pinnedAt: index < 220 ? date : nil)
            }
            let inserted = ClipboardStore.importStoredItems(inDatabaseAt: store.dbURL, entries)
            try #require(inserted == entries.count)
            store.load()
        }

        init(through lastStage: Stage) throws {
            try self.init()
            for stage in Stage.allCases {
                try advance(to: stage)
                if stage == lastStage { break }
            }
        }

        mutating func advance(to stage: Stage) throws {
            switch stage {
            case .initiallyDisabled:
                break
            case .enabled:
                try #require(store.setTextSearchEnabled(true))
                for (index, entry) in entries.enumerated() where entry.kind != .text && index % 7 != 0 {
                    try recognize("Common invoice" + Self.suffix(at: index), for: entry)
                }
            case .lateRecognition:
                try recognize("common invoice rare", for: entries[224])
            case .promotedAndPinned:
                store.promote(entries[400])
                store.togglePinned(entries[401])
            case .disabledWithMetadata:
                try #require(store.setTextSearchEnabled(false))
                store.promote(entries[401])
                let pinned = try #require(store.items.first { $0.id == entries[401].id })
                store.togglePinned(pinned)
                store.promote(entries[400])
            case .reenabled, .enabledAfterReopen:
                try #require(store.setTextSearchEnabled(true))
            case .rowDeleted:
                store.remove(entries[400])
                metadata.removeValue(forKey: entries[400].id)
            case .reopened:
                store.close()
                store.open()
                store.load()
            case .cleared:
                store.setTextSearchActive(false)
                store.setTextSearchActive(true)
                store.clearAll()
                let survivors = Set(store.items.map(\.id))
                metadata = metadata.filter { survivors.contains($0.key) }
            }
        }

        func results(
            for term: String, filter: ClipboardFilter
        ) -> (
            immediate: [ResultRow], recognized: [ResultRow]?
        ) {
            let pins = store.items.filter(\.isPinned).sorted {
                ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture)
            }
            guard !term.isEmpty else {
                return (filter.apply(to: pins + store.items.filter { !$0.isPinned }).map(ResultRow.init), nil)
            }

            var candidates = store.items
            if term.count >= 3 {
                var stored: [ClipboardItem] = []
                ClipboardStore.forEachStoredItem(inDatabaseAt: store.dbURL) { stored.append($0) }
                candidates = Array(stored.reversed())
            }
            let ordinary = candidates.filter { $0.matches(term) }
                .prefix(term.count < 3 ? Int.max : 200).filter { !$0.isPinned }
            let matchingPins = pins.filter { $0.matches(term) }
            let immediate = filter.apply(to: matchingPins + ordinary).map(ResultRow.init)
            guard store.textSearchEnabled, filter == .all || filter == .image || filter == .file else {
                return (immediate, nil)
            }

            let recognized = filter.apply(to: candidates).filter {
                metadata[$0.id]?.localizedCaseInsensitiveContains(term) == true
            }
            let recognizedIDs = Set(recognized.map(\.id))
            let visiblePins = pins.filter { $0.matches(term) || recognizedIDs.contains($0.id) }
            let ordinaryIDs = Set(ordinary.map(\.id))
            let extra = recognized.filter { !$0.isPinned }.prefix(200).filter { !ordinaryIDs.contains($0.id) }
            let remaining = max(0, 200 - filter.apply(to: ordinary).count)
            let settled = filter.apply(to: visiblePins + ordinary + Array(extra.prefix(remaining)))
            return (immediate, settled.map(ResultRow.init))
        }

        private mutating func recognize(_ text: String, for entry: ClipboardItem) throws {
            try #require(store.setExtractedText(text, for: entry, generation: store.extractionGeneration))
            metadata[entry.id] = text
        }

        private static func suffix(at index: Int) -> String {
            " \(index) café 日本語 say \"yes\"" + (index % 401 == 0 ? " rare" : "")
        }
    }
}
