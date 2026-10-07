import Foundation

@main
@MainActor
struct ExtensionStoreSessionTests {
    static var failures = 0

    static func main() async {
        let fixture = Fixture()
        let session = ExtensionStoreSession { query, page, category in
            try await fixture.fetch(query: query, page: page, category: category)
        }
        session.search("")
        await fixture.waitForRequests(1)
        session.search("github")
        await fixture.waitForRequests(2)
        fixture.answer(1, names: ["github"], hasMore: true)
        await settle()
        fixture.answer(0, names: ["stale"], hasMore: false)
        await settle()
        check("old search cannot replace current rows", session.listings.map(\.name) == ["github"])
        check("old search cannot reset pagination", session.hasMore)
        check("current search finishes loading", !session.isLoading)

        session.loadMore()
        session.loadMore()
        await fixture.waitForRequests(3)
        check("only one next-page request starts", fixture.requests.count == 3)
        check("next page keeps the query", fixture.requests[2].query == "github" && fixture.requests[2].page == 2)
        fixture.answer(2, names: ["github", "coffee", "coffee"], hasMore: false)
        await settle()
        check("pages append without duplicate identities", session.listings.map(\.name) == ["github", "coffee"])
        check("last page ends pagination", !session.hasMore)

        session.category = "Developer Tools"
        session.search("github")
        await fixture.waitForRequests(4)
        check("category changes start page one", fixture.requests[3].page == 1)
        check("category reaches the request", fixture.requests[3].category == "Developer Tools")
        session.close()
        fixture.answer(3, names: ["late"], hasMore: true)
        await settle()
        check("closed store stays empty", session.listings.isEmpty && !session.isLoading)

        session.search("")
        await fixture.waitForRequests(5)
        fixture.reject(4)
        await settle()
        check("failure is visible", session.failure != nil && !session.isLoading)
        session.search("", force: true)
        await fixture.waitForRequests(6)
        fixture.answer(5, names: ["retry"], hasMore: false)
        await settle()
        check("retry recovers", session.failure == nil && session.listings.first?.name == "retry")

        session.search("pending")
        await fixture.waitForRequests(7)
        session.showInstalled([listing("local")])
        fixture.answer(6, names: ["remote"], hasMore: true)
        await settle()
        check("Installed replaces a pending network search", session.listings.first?.name == "local" && !session.hasMore)
        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    static func listing(_ name: String) -> ExtensionListing {
        ExtensionListing(
            id: name, name: name, title: name, summary: "", author: "", lightIconURL: nil,
            darkIconURL: nil, commandCount: 0, downloadCount: nil,
            downloadURL: URL(filePath: "/fixture"), commitSHA: nil)
    }

    static func check(_ name: String, _ passed: Bool) {
        print("\(passed ? "ok" : "FAIL") \(name)")
        if !passed { failures += 1 }
    }

    @MainActor
    final class Fixture {
        struct Request {
            let query: String
            let page: Int
            let category: String?
            let continuation: CheckedContinuation<ExtensionStoreResponse.Page, any Error>
        }
        var requests: [Request] = []

        func fetch(query: String, page: Int, category: String?) async throws -> ExtensionStoreResponse.Page {
            try await withCheckedThrowingContinuation { continuation in
                requests.append(Request(query: query, page: page, category: category, continuation: continuation))
            }
        }

        func waitForRequests(_ count: Int) async {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(5)
            while requests.count < count && clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(1))
            }
            guard requests.count >= count else { fatalError("Request never arrived") }
        }

        func answer(_ index: Int, names: [String], hasMore: Bool) {
            requests[index].continuation.resume(returning: ExtensionStoreResponse.Page(
                listings: names.map(ExtensionStoreSessionTests.listing), totalResults: nil, hasMore: hasMore))
        }

        func reject(_ index: Int) {
            requests[index].continuation.resume(throwing: ExtensionStoreError.malformedResponse)
        }
    }
}
