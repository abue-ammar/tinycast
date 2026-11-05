import Foundation
import os

struct UpdateInstaller: Sendable {
    enum Phase: Sendable, Equatable {
        case downloading(received: Int64, expected: Int64)
        case extracting
        case verifying

        var message: String {
            switch self {
            case .downloading: return String(localized: "Downloading…")
            case .extracting: return String(localized: "Expanding…")
            case .verifying: return String(localized: "Verifying…")
            }
        }

        /// Only the download knows how far along it is; the rest are short, opaque steps.
        var fraction: Double? {
            guard case .downloading(let received, let expected) = self, expected > 0 else {
                return nil
            }
            return min(1, Double(received) / Double(expected))
        }
    }

    struct Staged: Sendable {
        let app: URL
        let isReleaseSigned: Bool
        let codeHash: Data
    }

    let bundleURL: URL
    let stagingDirectory: URL

    private static let logger = Logger(subsystem: "com.tinycast", category: "Updates")

    /// Everything short of the swap, which waits for quit so no old code runs on new files.
    func prepare(
        _ release: AvailableRelease, onProgress: @escaping @Sendable (Phase) -> Void
    ) async throws -> Staged {
        let location = bundleURL.deletingLastPathComponent()
        // The swap runs at quit, too late to report anything, so an unwritable copy is caught now.
        guard FileManager.default.isWritableFile(atPath: location.path),
            FileManager.default.isWritableFile(atPath: bundleURL.path)
        else { throw UpdateFailure.replaceFailed(location.path) }
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

        let releaseSigned = try await isReleaseSigned(archive, by: release.signatureURL)

        onProgress(.extracting)
        let staged = try await expand(archive, into: expanded)
        try? FileManager.default.removeItem(at: archive)

        onProgress(.verifying)
        do {
            let codeHash = try verify(staged, is: release, releaseSigned: releaseSigned)
            try Task.checkCancellation()
            return Staged(app: staged, isReleaseSigned: releaseSigned, codeHash: codeHash)
        } catch {
            try? FileManager.default.removeItem(at: expanded)
            throw error
        }
    }

    /// Anything can write to Caches before quit, so only the exact bytes verified may land.
    func install(_ staged: Staged) throws {
        defer { try? FileManager.default.removeItem(at: staged.app.deletingLastPathComponent()) }
        // Another install may have replaced the app since launch; never roll that back.
        guard Self.info(at: bundleURL)?["CFBundleShortVersionString"] as? String == runningVersion else {
            throw UpdateFailure.replaceFailed(bundleURL.path)
        }
        let codeHash = BundleSignature.trustedHash(
            of: staged.app, releaseSigned: staged.isReleaseSigned)
        guard codeHash == staged.codeHash else { throw UpdateFailure.replaceFailed(staged.app.path) }
        do {
            _ = try FileManager.default.replaceItemAt(
                bundleURL, withItemAt: staged.app, options: .usingNewMetadataOnly)
        } catch {
            throw UpdateFailure.replaceFailed(error.localizedDescription)
        }
    }

    private var runningVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// A missing signature is not fatal, since the running identity may still vouch for the bundle.
    private func isReleaseSigned(_ archive: URL, by signatureURL: URL?) async throws -> Bool {
        guard let signatureURL else { return false }
        let signature: Data
        do {
            signature = try await UpdateDownloader.data(from: signatureURL)
        } catch {
            try Task.checkCancellation()
            Self.logger.error(
                "Fetching the update signature failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        return UpdateSignature.isSigned(archive, by: signature)
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

    private func verify(
        _ staged: URL, is release: AvailableRelease, releaseSigned: Bool
    ) throws -> Data {
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
                expected: release.version.description, found: found ?? String(localized: "unknown"))
        }
        guard let codeHash = BundleSignature.trustedHash(of: staged, releaseSigned: releaseSigned)
        else { throw UpdateFailure.identityMismatch }
        return codeHash
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
