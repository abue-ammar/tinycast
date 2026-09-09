import AppKit

/// Opens a resolved destination; every platform effect the feature has lives here.
@MainActor
enum QuicklinkLauncher {
    enum Failure: LocalizedError, Equatable {
        case unresolvable(String)
        case missingFile(String)
        case missingApplication(String)
        case openFailed(target: String, detail: String)

        var errorDescription: String? {
            switch self {
            case .unresolvable(let link):
                return String(localized: "“\(link)” isn't a URL, file path, or deeplink.", bundle: .appLanguage)
            case .missingFile(let path):
                return String(localized: "Nothing exists at \(path) any more.", bundle: .appLanguage)
            case .missingApplication:
                return String(localized: "The app this quicklink opens with isn't installed any more.", bundle: .appLanguage)
            case .openFailed(let target, let detail):
                return String(localized: "macOS could not open \(target).\n\n\(detail)", bundle: .appLanguage)
            }
        }

        /// A missing handler is the one failure with a usable second option — the system default.
        var missingApplicationBundleID: String? {
            if case .missingApplication(let bundleID) = self { return bundleID }
            return nil
        }
    }

    /// Chromium and Firefox accept this, Safari ignores it, so passing it always is safe.
    private static let newWindowArgument = "--new-window"

    /// `openWithBundleID` nil means the system default handler.
    static func open(
        _ link: String, openWithBundleID: String?, inNewWindow: Bool
    ) async throws(Failure) {
        guard let destination = QuicklinkDestination.detect(link) else {
            throw .unresolvable(link)
        }
        let url: URL
        switch destination {
        case .web(let value), .network(let value), .deeplink(let value):
            url = value
        case .path(let path):
            // Checked first so a deleted folder names itself instead of failing as a silent no-op.
            guard FileManager.default.fileExists(atPath: path) else { throw .missingFile(path) }
            url = URL(fileURLWithPath: path)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        if inNewWindow { configuration.arguments = [newWindowArgument] }

        var application: URL?
        if let openWithBundleID {
            application = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: openWithBundleID)
            guard application != nil else { throw .missingApplication(openWithBundleID) }
        }

        do {
            if let application {
                _ = try await NSWorkspace.shared.open(
                    [url], withApplicationAt: application, configuration: configuration)
            } else {
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            }
        } catch {
            throw .openFailed(
                target: destination.displayText, detail: error.localizedDescription)
        }
    }
}
