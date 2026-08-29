import Foundation

/// Fetches a release archive, proves it is ours, and swaps it in. docs/features/updates.md
struct UpdateInstaller: Sendable {
    enum Phase: Sendable, Equatable {
        case downloading(received: Int64, expected: Int64)
        case extracting
        case verifying
        case replacing

        var message: String {
            switch self {
            case .downloading(let received, let expected):
                return "Downloading… \(Self.size(received)) of \(Self.size(expected))"
            case .extracting: return "Expanding…"
            case .verifying: return "Verifying…"
            case .replacing: return "Replacing Tinycast…"
            }
        }

        /// Only the download knows how far along it is; the rest are short, opaque steps.
        var fraction: Double? {
            guard case .downloading(let received, let expected) = self, expected > 0 else {
                return nil
            }
            return min(1, Double(received) / Double(expected))
        }

        private static func size(_ bytes: Int64) -> String {
            bytes.formatted(.byteCount(style: .file))
        }
    }

    let bundleURL: URL
    let stagingDirectory: URL

    func install(
        _ release: AvailableRelease, onProgress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        try? FileManager.default.createDirectory(
            at: stagingDirectory, withIntermediateDirectories: true)
        let archive = stagingDirectory.appendingPathComponent("\(release.tag).zip")
        let expanded = stagingDirectory.appendingPathComponent("expanded", isDirectory: true)
        try? FileManager.default.removeItem(at: expanded)

        onProgress(.downloading(received: 0, expected: release.assetSize))
        for try await event in UpdateDownloader.download(release, to: archive) {
            guard case .progress(let received, let expected) = event else { continue }
            onProgress(.downloading(received: received, expected: expected))
        }

        onProgress(.extracting)
        let staged = try await expand(archive, into: expanded)

        onProgress(.verifying)
        try verify(staged, is: release)

        onProgress(.replacing)
        do {
            _ = try FileManager.default.replaceItemAt(
                bundleURL, withItemAt: staged, options: .usingNewMetadataOnly)
        } catch {
            throw UpdateFailure.replaceFailed(error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: archive)
        try? FileManager.default.removeItem(at: expanded)
    }

    private func expand(_ archive: URL, into directory: URL) async throws -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `ditto` ships with macOS, keeps the bundle's seal intact, and Foundation has no unzip.
        let result = try await ToolRunner.run(
            URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", archive.path, directory.path])
        guard result.succeeded else { throw UpdateFailure.extractFailed(result.tail) }
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        // Named for its channel — "Tinycast Beta.app", not "Tinycast.app".
        guard let app = contents?.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateFailure.noAppInArchive
        }
        return app
    }

    private func verify(_ staged: URL, is release: AvailableRelease) throws {
        if Quarantine.isSet(on: staged) { Quarantine.clear(from: staged) }
        // Refuse rather than install something the user would then have to unquarantine by hand.
        guard !Quarantine.isSet(on: staged) else { throw UpdateFailure.quarantined }

        let info = Self.info(at: staged)
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateFailure.bundleMismatch
        }
        let found = info?["CFBundleShortVersionString"] as? String
        guard found == release.version.description else {
            throw UpdateFailure.versionMismatch(
                expected: release.version.description, found: found ?? "unknown")
        }
        guard BundleSignature.matchesRunningApp(staged) else { throw UpdateFailure.identityMismatch }
    }

    /// Off disk, not through `Bundle`, whose cache would answer for the old copy.
    private static func info(at bundleURL: URL) -> [String: Any]? {
        let url = bundleURL.appending(components: "Contents", "Info.plist")
        guard let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: Any]
    }
}
