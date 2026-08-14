import AppKit
import Foundation

/// A protocol, so the bridge has no hard dependency on the `ExtensionManager` that owns it.
@MainActor
protocol ExtensionHostContext: AnyObject {
    /// The extension whose command is running — the namespace for storage, cache and preferences.
    var activeExtensionName: String? { get }
    var storage: ExtensionStorage { get }
    /// The app a paste would land in — the palette's recorded `previousApp`.
    var pasteTarget: NSRunningApplication? { get }
    /// Every app bundle `getApplications()` reports, from the user's own search scopes.
    var applicationURLs: [URL] { get }

    func closeMainWindow(clearRootSearch: Bool)
    /// Bring the palette back after a command hid it — what `raycast://` means to an extension.
    func reopenPalette()
    func popToRoot()
    func clearSearchBar()
    func openPreferences(scope: String)
    func present(toast: ExtensionToast) -> Int
    func update(toast id: Int, with toast: ExtensionToast)
    func hide(toast id: Int)
    func showHUD(_ text: String)
    func confirmAlert(_ alert: ExtensionAlert) async -> Bool
    func openWithPicker(path: String) async
    func launch(command: String, extensionName: String?, arguments: [String: String]) throws
}

/// A toast as the palette shows it.
struct ExtensionToast: Sendable, Equatable, Identifiable {
    enum Style: String, Sendable {
        case success = "SUCCESS"
        case failure = "FAILURE"
        case animated = "ANIMATED"

        init(raw: String?) {
            self = Style(rawValue: raw ?? "SUCCESS") ?? .success
        }
    }

    struct Action: Sendable, Equatable {
        let title: String
        /// Echoed back to `runToastAction` so JS can find the callback.
        let token: String
    }

    var id: Int = 0
    var style: Style = .success
    var title: String = ""
    var message: String?
    var primaryAction: Action?
    var secondaryAction: Action?

    init(
        id: Int = 0, style: Style = .success, title: String = "", message: String? = nil,
        primaryAction: Action? = nil, secondaryAction: Action? = nil
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    init(payload: [String: RenderValue]) {
        style = Style(raw: payload["style"]?.stringValue)
        title = payload["title"]?.stringValue ?? ""
        message = payload["message"]?.stringValue
        primaryAction = ExtensionToast.action(from: payload["primaryAction"])
        secondaryAction = ExtensionToast.action(from: payload["secondaryAction"])
    }

    private static func action(from value: RenderValue?) -> Action? {
        guard let fields = value?.objectValue, let token = fields["token"]?.stringValue else {
            return nil
        }
        return Action(title: fields["title"]?.stringValue ?? "", token: token)
    }
}

struct ExtensionAlert: Sendable {
    var title: String
    var message: String?
    var primaryTitle: String
    var dismissTitle: String
    var isDestructive: Bool

    init(payload: [String: RenderValue]) {
        title = payload["title"]?.stringValue ?? "Are you sure?"
        message = payload["message"]?.stringValue
        let primary = payload["primaryAction"]?.objectValue
        primaryTitle = primary?["title"]?.stringValue ?? "Confirm"
        dismissTitle = payload["dismissAction"]?.objectValue?["title"]?.stringValue ?? "Cancel"
        isDestructive = primary?["style"]?.stringValue == "destructive"
    }
}

enum ExtensionHostError: LocalizedError {
    case noActiveExtension
    case unknown(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .noActiveExtension: return "No extension command is running."
        case .unknown(let what): return "Unknown host call '\(what)'."
        case .unsupported(let what): return "\(what) is not supported in Tinycast extensions."
        }
    }
}

@MainActor
final class ExtensionHostBridge: ExtensionHostAPI {
    weak var context: ExtensionHostContext?
    private let clipboardStore: ClipboardStore
    private let fetcher = ExtensionFetcher()

    init(clipboardStore: ClipboardStore) {
        self.clipboardStore = clipboardStore
    }

    func perform(api: String, method: String, arguments: [RenderValue]) async throws -> String {
        let value = try await dispatch(api: api, method: method, arguments: arguments)
        return ExtensionRuntime.jsonString(from: value)
    }

    private func dispatch(api: String, method: String, arguments: [RenderValue]) async throws -> Any? {
        switch api {
        case "clipboard": return try clipboard(method: method, arguments: arguments)
        case "storage": return try storage(method: method, arguments: arguments)
        case "cache": return try cache(method: method, arguments: arguments)
        case "window": return window(method: method, arguments: arguments)
        case "feedback": return try await feedback(method: method, arguments: arguments)
        case "system": return try await system(method: method, arguments: arguments)
        case "fetch": return try await fetcher.request(arguments.first)
        case "proc": return try await ExtensionAsyncProcess.run(arguments.first)
        default: throw ExtensionHostError.unknown("\(api).\(method)")
        }
    }

    private func requireContext() throws -> (ExtensionHostContext, String) {
        guard let context, let name = context.activeExtensionName else {
            throw ExtensionHostError.noActiveExtension
        }
        return (context, name)
    }

    // MARK: - Clipboard

    private func clipboard(method: String, arguments: [RenderValue]) throws -> Any? {
        switch method {
        case "copy", "paste":
            let content = arguments.first?.objectValue ?? [:]
            // A file goes on the pasteboard as a file, so it pastes as the picture it is.
            if let path = content["file"]?.stringValue, !path.isEmpty {
                writeFileToPasteboard(path)
                if method == "paste" { Paster.postCommandV() }
                return nil
            }
            guard let text = clipboardText(from: content) else { return nil }
            if method == "copy" {
                Paster.copyString(text)
            } else {
                Paster.pasteString(text, previousApp: context?.pasteTarget)
            }
            return nil

        case "clear":
            NSPasteboard.general.clearContents()
            return nil

        case "readText":
            return NSPasteboard.general.string(forType: .string) ?? ""

        case "read":
            var payload: [String: Any] = [:]
            if let text = NSPasteboard.general.string(forType: .string) { payload["text"] = text }
            if let url = NSPasteboard.general.string(forType: .URL) { payload["file"] = url }
            return payload

        default:
            throw ExtensionHostError.unknown("clipboard.\(method)")
        }
    }

    /// The file and its picture both: Finder takes the URL, a chat box takes the image data.
    private func writeFileToPasteboard(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var items: [NSPasteboardWriting] = [url as NSURL]
        if let image = NSImage(contentsOf: url) { items.append(image) }
        pasteboard.writeObjects(items)
    }

    private func clipboardText(from content: [String: RenderValue]) -> String? {
        if let text = content["text"]?.stringValue { return text }
        if let html = content["html"]?.stringValue { return html }
        return nil
    }

    // MARK: - LocalStorage

    private func storage(method: String, arguments: [RenderValue]) throws -> Any? {
        let (context, name) = try requireContext()
        switch method {
        case "get":
            guard let key = arguments.first?.stringValue else { return nil }
            return context.storage.localStorageValue(extension: name, key: key)?.jsonValue

        case "set":
            guard let key = arguments.first?.stringValue,
                let value = arguments[safe: 1].flatMap(ExtensionStorage.StoredValue.init(renderValue:))
            else { return nil }
            context.storage.setLocalStorage(extension: name, key: key, value: value)
            return nil

        case "remove":
            guard let key = arguments.first?.stringValue else { return nil }
            context.storage.removeLocalStorage(extension: name, key: key)
            return nil

        case "clear":
            context.storage.clearLocalStorage(extension: name)
            return nil

        case "all":
            return context.storage.allLocalStorage(extension: name).mapValues(\.jsonValue)

        default:
            throw ExtensionHostError.unknown("storage.\(method)")
        }
    }

    // MARK: - Cache

    private func cache(method: String, arguments: [RenderValue]) throws -> Any? {
        let (context, name) = try requireContext()
        let namespace = arguments.first?.stringValue ?? "default"
        switch method {
        case "set":
            // A nil key clears the namespace; a nil value removes one entry.
            let key = arguments[safe: 1]?.stringValue
            let value = arguments[safe: 2]?.stringValue
            context.storage.setCache(extension: name, namespace: namespace, key: key, value: value)
            return nil
        case "clear":
            context.storage.clearCache(extension: name, namespace: namespace)
            return nil
        default:
            throw ExtensionHostError.unknown("cache.\(method)")
        }
    }

    // MARK: - Window

    private func window(method: String, arguments: [RenderValue]) -> Any? {
        switch method {
        case "close":
            let options = arguments.first?.objectValue ?? [:]
            context?.closeMainWindow(clearRootSearch: options["clearRootSearch"]?.boolValue ?? false)
        case "popToRoot":
            context?.popToRoot()
        case "clearSearchBar":
            context?.clearSearchBar()
        case "openPreferences":
            context?.openPreferences(scope: arguments.first?.stringValue ?? "extension")
        default:
            break
        }
        return nil
    }

    // MARK: - Feedback

    private func feedback(method: String, arguments: [RenderValue]) async throws -> Any? {
        guard let context else { throw ExtensionHostError.noActiveExtension }
        switch method {
        case "showToast":
            guard let payload = arguments.first?.objectValue else { return nil }
            return context.present(toast: ExtensionToast(payload: payload))

        case "updateToast":
            guard let id = arguments.first?.doubleValue.map(Int.init),
                let payload = arguments[safe: 1]?.objectValue
            else { return nil }
            context.update(toast: id, with: ExtensionToast(payload: payload))
            return nil

        case "hideToast":
            if let id = arguments.first?.doubleValue.map(Int.init) { context.hide(toast: id) }
            return nil

        case "showHUD":
            context.showHUD(arguments.first?.stringValue ?? "")
            return nil

        case "confirmAlert":
            guard let payload = arguments.first?.objectValue else { return false }
            return await context.confirmAlert(ExtensionAlert(payload: payload))

        default:
            throw ExtensionHostError.unknown("feedback.\(method)")
        }
    }

    // MARK: - System

    private func system(method: String, arguments: [RenderValue]) async throws -> Any? {
        switch method {
        case "open":
            guard let target = arguments.first?.stringValue else { return nil }
            open(target: target, application: arguments[safe: 1]?.stringValue)
            return nil

        case "openWith":
            await context?.openWithPicker(path: arguments.first?.stringValue ?? "")
            return nil

        case "showInFinder":
            guard let path = arguments.first?.stringValue else { return nil }
            AppLauncher.showInFinder(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            return nil

        case "trash":
            let paths = (arguments.first?.arrayValue ?? []).compactMap(\.stringValue)
            for path in paths {
                try? FileManager.default.trashItem(
                    at: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
                    resultingItemURL: nil)
            }
            return nil

        case "applications":
            return applications(forPath: arguments.first?.stringValue)

        case "defaultApplication":
            guard let path = arguments.first?.stringValue,
                let url = NSWorkspace.shared.urlForApplication(
                    toOpen: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            else { throw ExtensionHostError.unsupported("getDefaultApplication") }
            return describe(application: url)

        case "frontmostApplication":
            guard let app = context?.pasteTarget ?? NSWorkspace.shared.frontmostApplication,
                let url = app.bundleURL
            else { throw ExtensionHostError.unsupported("getFrontmostApplication") }
            return describe(application: url)

        case "selectedText":
            return try selectedText()

        case "selectedFinderItems":
            return try finderSelection()

        case "launchCommand":
            let options = arguments.first?.objectValue ?? [:]
            guard let name = options["name"]?.stringValue else {
                throw ExtensionHostError.unsupported("launchCommand without a name")
            }
            var launchArguments: [String: String] = [:]
            for (key, value) in options["arguments"]?.objectValue ?? [:] {
                launchArguments[key] = value.stringValue
            }
            try context?.launch(
                command: name, extensionName: options["extensionName"]?.stringValue,
                arguments: launchArguments)
            return nil

        case "updateCommandMetadata":
            // Subtitle metadata only shows on menu-bar commands, which Tinycast doesn't run.
            return nil

        default:
            throw ExtensionHostError.unknown("system.\(method)")
        }
    }

    private func open(target: String, application: String?) {
        let url =
            URL(string: target).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        // Extensions address Raycast by scheme; handing that to the workspace would launch Raycast.
        if let scheme = url.scheme, scheme == "raycast" || scheme == "raycastinternal" {
            openRaycastURL(url)
            return
        }
        guard let appIdentifier = application else {
            NSWorkspace.shared.open(url)
            return
        }
        let appURL =
            appIdentifier.hasPrefix("/")
            ? URL(fileURLWithPath: appIdentifier)
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: appIdentifier)
        guard let appURL else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open(
            [url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil)
    }

    /// A command URL runs it when installed; every other Raycast URL just brings the palette back.
    private func openRaycastURL(_ url: URL) {
        let path = url.pathComponents.filter { $0 != "/" }
        if url.host == "extensions", path.count >= 3,
            (try? context?.launch(command: path[2], extensionName: path[1], arguments: [:])) != nil
        {
            return
        }
        context?.reopenPalette()
    }

    private func applications(forPath path: String?) -> [[String: Any]] {
        let urls: [URL]
        if let path, !path.isEmpty {
            let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            urls = NSWorkspace.shared.urlsForApplications(toOpen: target)
        } else {
            urls = context?.applicationURLs ?? []
        }
        return urls.map(describe(application:))
    }

    private func describe(application url: URL) -> [String: Any] {
        let bundle = Bundle(url: url)
        let name =
            (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return [
            "name": name, "path": url.path, "bundleId": bundle?.bundleIdentifier ?? NSNull(),
            "localizedName": name
        ]
    }

    /// Reuses the Accessibility grant the paste path already needs.
    private func selectedText() throws -> String {
        guard Permissions.ensureAccessibility() else {
            throw ExtensionHostError.unsupported("getSelectedText without the Accessibility permission")
        }
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard
            AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
                == .success,
            let element = focused as! AXUIElement?
        else { throw ExtensionHostError.unsupported("getSelectedText (no focused element)") }

        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
                == .success, let text = value as? String
        else { throw ExtensionHostError.unsupported("getSelectedText (no selection)") }
        return text
    }

    /// Joined on a linefeed, which Finder forbids in a name; the comma AppleScript defaults to would
    /// cut any path that contains one into two paths that exist nowhere.
    private func finderSelection() throws -> [[String: String]] {
        let script = """
            set AppleScript's text item delimiters to linefeed
            tell application "Finder" to set chosen to (get selection as alias list)
            set paths to {}
            repeat with one in chosen
                set end of paths to POSIX path of one
            end repeat
            return paths as text
            """
        guard let apple = NSAppleScript(source: script) else { return [] }
        var error: NSDictionary?
        let result = apple.executeAndReturnError(&error)
        guard error == nil else { return [] }
        return result.stringValue?
            .split(separator: "\n")
            .map { ["path": String($0)] } ?? []
    }
}
