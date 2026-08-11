import AppKit

@MainActor
enum NoteLinkLauncher {
    enum Failure: LocalizedError {
        case missingFile(URL)
        case openFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingFile(let url):
                "Nothing exists at \(url.path)."
            case .openFailed(let detail):
                "macOS could not open the destination.\n\n\(detail)"
            }
        }
    }

    static func open(_ destination: NoteLinkDestination) async throws(Failure) {
        if case .file(let url) = destination,
            !FileManager.default.fileExists(atPath: url.path)
        {
            throw .missingFile(url)
        }
        do {
            _ = try await NSWorkspace.shared.open(
                destination.url,
                configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw .openFailed(error.localizedDescription)
        }
    }
}
