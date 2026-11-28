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
    /// Moves when the icon file does, so a repack or an update retires the cached bitmap.
    let iconStamp: Int

    var id: String { manifest.id }
    var executableURL: URL { url.appending(path: "Contents/MacOS/\(id)", directoryHint: .notDirectory) }
    var iconURL: URL { Self.iconURL(of: manifest, in: url) }

    private static func iconURL(of manifest: ExtensionManifest, in url: URL) -> URL {
        url.appending(path: "Contents/Resources/\(manifest.icon)", directoryHint: .notDirectory)
    }

    /// Every bundle that may run now, read from manifests alone, so listing starts no process.
    static func available(developerMode: Bool) -> [ExtensionBundle] {
        #if DEBUG
            if developerMode { return scan(developerFolder, origin: .developer) }
        #endif
        return []
    }

    #if DEBUG
        /// A symlink to an extension's `.build/<id>.tcext` keeps it current as `tinycast pack` reruns.
        static var developerFolder: URL {
            AppPaths.applicationSupport().appending(path: "DeveloperExtensions", directoryHint: .isDirectory)
        }
    #endif

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.abueammar.tinycast", category: "Extensions")

    static func load(at url: URL, origin: Origin) throws -> ExtensionBundle {
        let manifestURL = url.appending(
            path: "Contents/Resources/extension.json", directoryHint: .notDirectory)
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.id == url.deletingPathExtension().lastPathComponent, hasReadableCommands(manifest)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let modified = try? iconURL(of: manifest, in: url)
            .resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return ExtensionBundle(
            url: url, manifest: manifest, origin: origin,
            iconStamp: modified.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0)
    }

    /// Plain decoding checks shape only; a row's entry ID needs unique, kebab-case command names.
    private static func hasReadableCommands(_ manifest: ExtensionManifest) -> Bool {
        let names = manifest.commands.map(\.name)
        return Set(names).count == names.count
            && names.allSatisfy { $0.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil }
    }

    /// Every bundle in `folder` that reads, by id; one that doesn't is logged and left out.
    static func scan(_ folder: URL, origin: Origin) -> [ExtensionBundle] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
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
