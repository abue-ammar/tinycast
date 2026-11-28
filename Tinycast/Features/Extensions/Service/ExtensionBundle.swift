import Foundation
import os

/// One packed `<id>.tcext`: where it lives, what its manifest says and where it came from.
struct ExtensionBundle: Sendable, Equatable {
    enum Origin: Sendable {
        case store
        #if DEBUG
            /// Packed on this Mac and run without the Store or the signature check.
            case developer
        #endif
    }

    let url: URL
    let manifest: ExtensionManifest
    let origin: Origin

    var id: String { manifest.id }
    var executableURL: URL { url.appending(path: "Contents/MacOS/\(id)", directoryHint: .notDirectory) }

    #if DEBUG
        /// A symlink to an extension's `.build/<id>.tcext` keeps it current as `tinycast pack` reruns.
        static var developerFolder: URL {
            AppPaths.applicationSupport().appending(path: "DeveloperExtensions", directoryHint: .isDirectory)
        }
    #endif

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abueammar.tinycast", category: "Extensions")

    static func load(at url: URL, origin: Origin) throws -> ExtensionBundle {
        let manifestURL = url.appending(path: "Contents/Resources/extension.json", directoryHint: .notDirectory)
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.id == url.deletingPathExtension().lastPathComponent else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return ExtensionBundle(url: url, manifest: manifest, origin: origin)
    }

    /// Every bundle in `folder` that reads, by id; one that doesn't is logged and left out.
    static func scan(_ folder: URL, origin: Origin) -> [ExtensionBundle] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "tcext" }.compactMap { url in
            do {
                return try load(at: url.resolvingSymlinksInPath(), origin: origin)
            } catch {
                logger.error("Skipped \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
                return nil
            }
        }
        .sorted { $0.id < $1.id }
    }
}
