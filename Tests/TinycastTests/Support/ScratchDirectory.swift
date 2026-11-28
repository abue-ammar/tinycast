import Foundation

/// A directory of the test's own under `temporaryDirectory`, removed when the test lets go of it.
final class ScratchDirectory: Sendable {
    let url: URL

    init(_ label: String = "scratch") throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "tinycast-\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
