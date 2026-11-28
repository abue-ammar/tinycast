import Foundation
import Testing

/// A file under `Tests/TinycastTests/Fixtures/`, read from the test bundle that carries it.
enum Fixture {
    static func url(_ path: String) throws -> URL {
        let root = try #require(Bundle(for: BundleToken.self).resourceURL).appending(path: "Fixtures")
        let url = root.appending(path: path)
        try #require(FileManager.default.fileExists(atPath: url.path), "no fixture at Fixtures/\(path)")
        return url
    }

    private final class BundleToken {}
}
