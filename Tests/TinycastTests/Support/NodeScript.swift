import Foundation
import Testing

@testable import Tinycast

/// A Node fixture installed as an executable in a scratch `bin`, with the shell's `node` beside it.
struct NodeScript {
    let executable: URL
    let node: URL

    /// A test host inherits no shell PATH, so a launch that leads with this folder finds `node`.
    init(_ fixture: String, in scratch: ScratchDirectory, named name: String) async throws {
        let bin = scratch.url.appending(path: "bin", directoryHint: .isDirectory)
        executable = bin.appending(path: name)
        node = bin.appending(path: "node")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixture.url(fixture), to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let found = try #require(await ExecutableLocator.locate("node"), "the stub needs Node")
        try FileManager.default.createSymbolicLink(at: node, withDestinationURL: found)
    }
}
