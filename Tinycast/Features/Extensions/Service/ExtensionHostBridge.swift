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
    func authorizeOAuth(url: URL, state: String?) async throws -> [String: String]
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

    var id: Int = 0
    var style: Style = .success
    var title: String
    var message: String?
    var primaryTitle: String?
    var primaryAction: String?
    var secondaryTitle: String?
    var secondaryAction: String?

    init(
        title: String, message: String? = nil, style: Style = .success, primaryTitle: String? = nil,
        primaryAction: String? = nil, secondaryTitle: String? = nil, secondaryAction: String? = nil
    ) {
        self.title = title
        self.message = message
        self.style = style
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    init?(json: [String: RenderValue]) {
        guard let title = json["title"]?.stringValue else { return nil }
        self.init(
            title: title,
            message: json["message"]?.stringValue,
            style: Style(raw: json["style"]?.stringValue),
            primaryTitle: json["primaryTitle"]?.stringValue,
            primaryAction: json["primaryAction"]?.handlerID,
            secondaryTitle: json["secondaryTitle"]?.stringValue,
            secondaryAction: json["secondaryAction"]?.handlerID
        )
    }
}

/// A question dialog hoisted out of the extension.
struct ExtensionAlert: Sendable, Equatable {
    var title: String
    var message: String
    var primaryTitle: String
    var dismissTitle: String
    var isDestructive: Bool

    init?(json: [String: RenderValue]) {
        guard let title = json["title"]?.stringValue else { return nil }
        self.title = title
        self.message = json["message"]?.stringValue ?? ""
        let primary = json["primaryAction"]?.objectValue ?? [:]
        self.primaryTitle = primary["title"]?.stringValue ?? "Confirm"
        let dismiss = json["dismissAction"]?.objectValue ?? [:]
        self.dismissTitle = dismiss["title"]?.stringValue ?? "Cancel"
        let rawStyle = primary["style"]?.stringValue ?? "DEFAULT"
        self.isDestructive = rawStyle.uppercased() == "DESTRUCTIVE"
    }
}

enum ExtensionHostError: LocalizedError {
    case unknown(String)
    case noActiveExtension
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unknown(let call): return "Unknown host call: \(call)"
        case .noActiveExtension: return "No extension is currently running."
        case .unsupported(let feature): return "\(feature) is not supported in Tinycast."
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
        case "oauth": return try await oauth(method: method, arguments: arguments)
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

    private func clipboardText(from content: [String: RenderValue]) -> String? {
        if let text = content["text"]?.stringValue { return text }
        if let number = content["number"]?.doubleValue {
            return number == number.rounded() && number.magnitude < 1e15
                ? String(Int(number)) : String(number)
        }
        return nil
    }

    private func writeFileToPasteboard(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    // MARK: - LocalStorage

    private func storage(method: String, arguments: [RenderValue]) throws -> Any? {
        let (context, name) = try requireContext()
        let storage = context.storage
        switch method {
        case "get":
            guard let key = arguments.first?.stringValue else { return nil }
            return storage.localStorageValue(extension: name, key: key)?.jsonValue

        case "set":
            guard let key = arguments.first?.stringValue,
                let renderValue = arguments.dropFirst().first,
                let stored = ExtensionStorage.StoredValue(renderValue: renderValue)
            else { return nil }
            storage.setLocalStorage(extension: name, key: key, value: stored)
            return nil

        case "remove":
            guard let key = arguments.first?.stringValue else { return nil }
            storage.removeLocalStorage(extension: name, key: key)
            return nil

        case "clear":
            storage.clearLocalStorage(extension: name)
            return nil

        case "all":
            return storage.allLocalStorage(extension: name).mapValues(\.jsonValue)

        default:
            throw ExtensionHostError.unknown("storage.\(method)")
        }
    }

    // MARK: - Cache

    private func cache(method: String, arguments: [RenderValue]) throws -> Any? {
        let (context, name) = try requireContext()
        let storage = context.storage
        let namespace = arguments.first?.stringValue ?? ""

        switch method {
        case "set":
            let key = arguments.dropFirst().first?.stringValue
            let value = arguments.dropFirst(2).first?.stringValue
            storage.setCache(extension: name, namespace: namespace, key: key, value: value)
            return nil

        case "all":
            return storage.caches(extension: name)

        default:
            throw ExtensionHostError.unknown("cache.\(method)")
        }
    }

    // MARK: - Window

    private func window(method: String, arguments: [RenderValue]) -> Any? {
        switch method {
        case "close":
            let clear = arguments.first?.objectValue?["clearRootSearch"]?.boolValue ?? false
            context?.closeMainWindow(clearRootSearch: clear)
        case "popToRoot":
            context?.popToRoot()
        case "clearSearchBar":
            context?.clearSearchBar()
        default:
            break
        }
        return nil
    }

    // MARK: - Feedback

    private func feedback(method: String, arguments: [RenderValue]) async throws -> Any? {
        switch method {
        case "showToast":
            guard let json = arguments.first?.objectValue,
                let toast = ExtensionToast(json: json)
            else { return 0 }
            return context?.present(toast: toast) ?? 0

        case "updateToast":
            guard let id = arguments.first?.numberValue.flatMap({ Int($0) }),
                let json = arguments.dropFirst().first?.objectValue,
                let toast = ExtensionToast(json: json)
            else { return nil }
            context?.update(toast: id, with: toast)
            return nil

        case "hideToast":
            guard let id = arguments.first?.numberValue.flatMap({ Int($0) }) else { return nil }
            context?.hide(toast: id)
            return nil

        case "showHUD":
            guard let text = arguments.first?.stringValue else { return nil }
            context?.showHUD(text)
            return nil

        case "confirmAlert":
            guard let json = arguments.first?.objectValue,
                let alert = ExtensionAlert(json: json)
            else { return false }
            return await context?.confirmAlert(alert) ?? false

        default:
            throw ExtensionHostError.unknown("feedback.\(method)")
        }
    }

    // MARK: - System

    private func system(method: String, arguments: [RenderValue]) async throws -> Any? {
        switch method {
        case "open":
            guard let target = arguments.first?.stringValue else { return nil }
            let application = arguments.dropFirst().first?.stringValue
            open(target: target, application: application)
            return nil

        case "openWithPicker":
            guard let path = arguments.first?.stringValue else { return nil }
            await context?.openWithPicker(path: path)
            return nil

        case "openPreferences":
            let scope = arguments.first?.stringValue ?? "extension"
            context?.openPreferences(scope: scope)
            return nil

        case "frontmostApplication":
            guard let app = NSWorkspace.shared.frontmostApplication,
                let url = app.bundleURL
            else { return nil }
            return describe(application: url)

        case "applications":
            let path = arguments.first?.stringValue
            return applications(forPath: path)

        case "selectedText":
            return try selectedText()

        case "finderSelection":
            return try finderSelection()

        default:
            throw ExtensionHostError.unknown("system.\(method)")
        }
    }

    // MARK: - OAuth

    private func oauth(method: String, arguments: [RenderValue]) async throws -> Any? {
        let (_, name) = try requireContext()
        let options = arguments.first?.objectValue ?? [:]
        let providerId = options["providerId"]?.stringValue

        switch method {
        case "authorize":
            guard let urlString = options["url"]?.stringValue,
                let url = URL(string: urlString)
            else {
                throw ExtensionHostError.unsupported("oauth.authorize requires a valid url")
            }
            let state = options["state"]?.stringValue
            guard let context else {
                throw ExtensionHostError.noActiveExtension
            }
            return try await context.authorizeOAuth(url: url, state: state)

        case "getTokens":
            guard let json = ExtensionOAuthKeychain.getTokens(extensionName: name, providerId: providerId) else {
                return nil
            }
            if let data = json.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data)
            {
                return obj
            }
            return json

        case "setTokens":
            guard let tokens = options["tokens"] else { return nil }
            let jsonString: String
            if let obj = tokens.objectValue {
                let dict = obj.mapValues(\.jsonValue)
                guard let data = try? JSONSerialization.data(withJSONObject: dict),
                    let str = String(data: data, encoding: .utf8)
                else { return nil }
                jsonString = str
            } else if let str = tokens.stringValue {
                jsonString = str
            } else {
                return nil
            }
            _ = ExtensionOAuthKeychain.setTokens(jsonString, extensionName: name, providerId: providerId)
            return nil

        case "removeTokens":
            _ = ExtensionOAuthKeychain.removeTokens(extensionName: name, providerId: providerId)
            return nil

        default:
            throw ExtensionHostError.unknown("oauth.\(method)")
        }
    }

    private func open(target: String, application: String?) {
        let url =
            URL(string: target).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        // Extensions address Raycast by scheme; handing that to the workspace would launch Raycast.
        if let scheme = url.scheme, scheme == "raycast" || scheme == "raycastinternal" || scheme == "tinycast" {
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
        if ExtensionOAuthSession.handleCallbackURL(url) {
            return
        }
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

    /// Reads the app the palette displaced, never the system-wide focus, which is our own field here.
    private func selectedText() throws -> String {
        guard Permissions.ensureAccessibility() else {
            throw ExtensionHostError.unsupported("getSelectedText without the Accessibility permission")
        }
        guard let target = context?.pasteTarget,
            target.processIdentifier != NSRunningApplication.current.processIdentifier
        else { throw ExtensionHostError.unsupported("getSelectedText (no target application)") }

        guard let text = AccessibilityText.selection(in: target), !text.isEmpty else {
            throw ExtensionHostError.unsupported("getSelectedText (no selection)")
        }
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
