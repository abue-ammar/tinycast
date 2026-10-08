import Darwin
import Foundation
import Testing

@main
@Suite(.serialized)
struct FSearchTests {
    static func main() async {
        let status: CInt = await Testing.__swiftPMEntryPoint()
        exit(status)
    }

    @Test func scopesAreLiteralAndBounded() throws {
        let scope = URL(fileURLWithPath: "/Users/test/Book (draft)")
        let request = try #require(FSearchRequest(query: "annul report", directories: [scope]))
        let pattern = try NSRegularExpression(pattern: request.path)
        func matches(_ path: String) -> Bool {
            pattern.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
        }
        #expect(matches("/Users/test/Book (draft)/annual report.pdf"))
        #expect(!matches("/Users/test/Book (draft) backup/annual report.pdf"))
        #expect(!matches("/Users/test/Book draft/annual report.pdf"))
        #expect(request.limit == FileSearchQuery.candidateLimit)
        #expect(request.q == "annul report")
    }

    @Test(arguments: [
        "", "  ", "a", "ab", "grep:secret", "in:/", "foo limit:900000", "!report", "^report", "report$",
        "\"report\"", "résumé", "отчёт", "a b c d e f g h i"
    ])
    func unsupportedInputUsesSpotlight(_ query: String) {
        #expect(FSearchRequest(query: query, directories: [URL(fileURLWithPath: "/tmp")]) == nil)
    }

    @Test func emptyScopesNeverSearchTheDisk() {
        #expect(FSearchRequest(query: "report", directories: []) == nil)
    }

    @Test func multipleScopesAndRoot() throws {
        let request = try #require(
            FSearchRequest(
                query: "main.swift",
                directories: [
                    URL(fileURLWithPath: "/tmp/A"), URL(fileURLWithPath: "/tmp/B")
                ]))
        let pattern = try NSRegularExpression(pattern: request.path)
        for path in ["/tmp/A/main.swift", "/tmp/B/sub/main.swift"] {
            #expect(pattern.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil)
        }
        let root = try #require(FSearchRequest(query: "main", directories: [URL(fileURLWithPath: "/")]))
        #expect(root.path == "^/")
    }

    @Test func readsFragmentedResponse() async throws {
        let request = try #require(
            FSearchRequest(query: "report", directories: [URL(fileURLWithPath: "/tmp")]))
        try await withServer(chunks: [
            "{\"ok\":true,", "\"hits\":[{\"path\":\"/tmp/report.pdf\",\"score\":90}]}\n"
        ]) { path in
            let hits = try FSearchClient.search(request, socketPath: path)
            #expect(hits.map(\.path) == ["/tmp/report.pdf"])
        }
    }

    @Test(arguments: [
        "{\"ok\":false,\"error\":\"indexing\"}\n", "{}\n", "not json\n", "{\"ok\":true}",
        "{\"ok\":true,\"hits\":null}\n"
    ])
    func rejectsFailedOrIncompleteResponse(_ response: String) async throws {
        let request = try #require(
            FSearchRequest(query: "report", directories: [URL(fileURLWithPath: "/tmp")]))
        try await withServer(chunks: [response]) { path in
            #expect(throws: (any Error).self) {
                try FSearchClient.search(request, socketPath: path)
            }
        }
    }

    @Test func boundsResponseSize() async throws {
        let request = try #require(
            FSearchRequest(query: "report", directories: [URL(fileURLWithPath: "/tmp")]))
        try await withServer(chunks: [String(repeating: "x", count: 1_048_577)]) { path in
            #expect(throws: (any Error).self) {
                try FSearchClient.search(request, socketPath: path)
            }
        }
    }

    @Test func boundsUnresponsiveServer() async throws {
        let request = try #require(
            FSearchRequest(query: "report", directories: [URL(fileURLWithPath: "/tmp")]))
        try await withServer(chunks: [], delay: .milliseconds(150)) { path in
            let start = ContinuousClock.now
            #expect(throws: (any Error).self) {
                try FSearchClient.search(request, socketPath: path, timeout: .milliseconds(30))
            }
            #expect(start.duration(to: .now) < .milliseconds(120))
        }
    }

    @Test func emptySuccessIsNotFailure() async throws {
        let request = try #require(
            FSearchRequest(query: "report", directories: [URL(fileURLWithPath: "/tmp")]))
        try await withServer(chunks: ["{\"ok\":true,\"hits\":[]}\n"]) { path in
            let hits = try FSearchClient.search(request, socketPath: path)
            #expect(hits.isEmpty)
        }
    }

    @Test func servicePreservesScopeIgnoreRulesAndEngineOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["report-second.txt", "report-first.txt", ".report-hidden", "report.tmp"]
        for name in names { try Data().write(to: root.appending(path: name)) }
        let paths = names.map { root.appending(path: $0).path }
        let response: [String: Any] = [
            "ok": true,
            "hits":
                (["/etc/passwd"] + paths + paths).map { ["path": $0] }
        ]
        let data = try JSONSerialization.data(withJSONObject: response)
        let text = try #require(String(data: data, encoding: .utf8)) + "\n"
        let policy = FileSearchPolicy(
            scopes: [root.path], ignorePatterns: ["*.tmp"], homeDirectory: root.deletingLastPathComponent())
        try await withServer(chunks: [text]) { socket in
            let results = try FileSearchService.search(query: "report", policy: policy, fsearchSocket: socket)
            #expect(results.map(\.name) == ["report-second.txt", "report-first.txt"])
        }
    }

    @Test func homeRootItemsRespectIgnoresWithEmptyDaemonResults() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: root.appending(path: "Documents"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "report.tmp"))
        let policy = FileSearchPolicy(scopes: ["~"], ignorePatterns: ["*.tmp"], homeDirectory: root)
        try await withServer(chunks: ["{\"ok\":true,\"hits\":[]}\n"]) { socket in
            let results = try FileSearchService.search(query: "report", policy: policy, fsearchSocket: socket)
            #expect(results.isEmpty)
        }
    }

    @Test func scopeAliasesResolveToCanonicalPaths() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            .resolvingSymlinksInPath()
        let directory = root.appending(path: "Documents")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = directory.appending(path: "report.txt")
        try Data().write(to: file)
        let alias = root.appending(path: "Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: directory)
        var scopes = [alias]
        let differentCase = root.appending(path: "documents")
        if FileManager.default.fileExists(atPath: differentCase.path) { scopes.append(differentCase) }
        let data = try JSONSerialization.data(withJSONObject: ["ok": true, "hits": [["path": file.path]]])
        let text = try #require(String(data: data, encoding: .utf8)) + "\n"
        for scope in scopes {
            let policy = FileSearchPolicy(scopes: [scope.path], ignorePatterns: [], homeDirectory: root)
            try await withServer(chunks: [text]) { socket in
                let results = try FileSearchService.search(
                    query: "report", policy: policy, fsearchSocket: socket)
                #expect(results.map(\.id) == [file.path])
            }
        }
    }

    private func withServer(
        chunks: [String], delay: Duration = .zero,
        operation: (String) throws -> Void
    ) async throws {
        let path = "/tmp/tinycast-\(UUID().uuidString).sock"
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(listener >= 0)
        defer { close(listener); unlink(path) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            Array(path.utf8CString).withUnsafeBytes { target.copyBytes(from: $0) }
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bound == 0 && listen(listener, 1) == 0)
        let server = Task.detached {
            var waiting = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&waiting, 1, 1_000) > 0 else { return }
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { return }
            defer { close(connection) }
            var enabled: Int32 = 1
            _ = setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &enabled, 4)
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            _ = setsockopt(
                connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
            var buffer = [UInt8](repeating: 0, count: 32_768)
            guard recv(connection, &buffer, buffer.count, 0) > 0 else { return }
            try? await Task.sleep(for: delay)
            for chunk in chunks {
                let data = Data(chunk.utf8)
                let sent = data.withUnsafeBytes { bytes -> Bool in
                    var offset = 0
                    while offset < bytes.count {
                        let count = send(
                            connection, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                        guard count > 0 else { return false }
                        offset += count
                    }
                    return true
                }
                guard sent else { return }
            }
        }
        do {
            try operation(path)
        } catch {
            await server.value
            throw error
        }
        await server.value
    }

}
