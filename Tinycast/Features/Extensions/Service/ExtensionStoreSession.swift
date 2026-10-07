import Foundation
import Observation

@MainActor
@Observable
final class ExtensionStoreSession {
    typealias Search = @Sendable (String, Int, String?) async throws -> ExtensionStoreResponse.Page

    private(set) var listings: [ExtensionListing] = []
    private(set) var isLoading = false
    private(set) var failure: String?
    private(set) var hasMore = false
    private(set) var detail: ExtensionListing?
    private(set) var installedNames: Set<String> = []
    private(set) var detailLoading = false
    private(set) var detailFailure: String?
    var category: String?
    var installedOnly = false
    var progress: [String: String] = [:]
    var installFailures: [String: String] = [:]

    @ObservationIgnored private let fetch: Search
    @ObservationIgnored private var query: String?
    @ObservationIgnored private var requestedCategory: String?
    @ObservationIgnored private var page = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?

    init(fetch: @escaping Search = { query, page, category in
        try await ExtensionStoreClient().search(query, page: page, category: category)
    }) {
        self.fetch = fetch
    }

    func search(_ query: String, force: Bool = false) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard force || trimmed != self.query || category != requestedCategory else { return }
        searchTask?.cancel()
        generation += 1
        self.query = trimmed
        requestedCategory = category
        page = 0
        listings = []
        failure = nil
        hasMore = false
        isLoading = true
        request(page: 1, debounce: !trimmed.isEmpty)
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        isLoading = true
        failure = nil
        request(page: page + 1, debounce: false)
    }

    private func request(page: Int, debounce: Bool) {
        let generation = generation
        let query = query ?? ""
        let category = requestedCategory
        let fetch = fetch
        searchTask = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(250)) }
                let result = try await fetch(query, page, category)
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                var known = Set(self.listings.map(\.id))
                self.listings += result.listings.filter { known.insert($0.id).inserted }
                self.page = page
                self.hasMore = result.hasMore
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self, self.generation == generation else { return }
                self.failure = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func showDetails(_ listing: ExtensionListing) {
        detailTask?.cancel()
        detail = listing
        detailFailure = nil
        detailLoading = false
        guard let handle = listing.ownerHandle ?? listing.authorHandle else { return }
        detailLoading = true
        detailTask = Task { [weak self] in
            do {
                let fresh = try await ExtensionStoreClient().lookup(handle: handle, name: listing.name)
                guard !Task.isCancelled, let self else { return }
                guard let fresh else { throw ExtensionStoreError.notAnExtension }
                self.detail = fresh
                self.detailLoading = false
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.detailFailure = error.localizedDescription
                self.detailLoading = false
            }
        }
    }

    func showInstalled(_ listings: [ExtensionListing]) {
        searchTask?.cancel()
        generation += 1
        self.listings = listings
        isLoading = false
        failure = nil
        hasMore = false
    }

    func setInstalledNames(_ names: Set<String>) { installedNames = names }

    func suspend() {
        searchTask?.cancel()
        generation += 1
        query = nil
        isLoading = false
    }

    func close() {
        searchTask?.cancel()
        detailTask?.cancel()
        searchTask = nil
        detailTask = nil
        generation += 1
        query = nil
        listings = []
        hasMore = false
        detail = nil
        isLoading = false
        detailLoading = false
        failure = nil
        detailFailure = nil
    }

    isolated deinit {
        searchTask?.cancel()
        detailTask?.cancel()
    }
}
