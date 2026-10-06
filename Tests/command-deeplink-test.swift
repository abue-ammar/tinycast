import Foundation

@main
@MainActor
struct CommandDeepLinkTests {
    static var failures = 0
    static var passes = 0

    static func check(_ name: String, _ condition: Bool) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(name)")
        }
    }

    static func main() {
        copiedCommands()
        invalidNativeLinks()
        extensionLinks()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func copiedCommands() {
        var addresses = Set<URL>()
        for command in CommandID.allCases where !command.isQueryDriven {
            guard let url = CommandDeepLink.url(for: command) else {
                check("\(command.name) has an address", false)
                continue
            }
            check("copied \(command.name) opens Tinycast", url.scheme == "tinycast")
            check("copied \(command.name) is claimed", CommandDeepLink.claims(url))
            check("copied \(command.name) dispatches its command", CommandDeepLink.parse(url) == command)
            check("command addresses are unique", addresses.insert(url).inserted)
        }
        check(
            "emoji uses the documented address",
            CommandDeepLink.url(for: .searchEmoji)?.absoluteString == "tinycast://command/search-emoji")
        check(
            "camera uses the documented address",
            CommandDeepLink.url(for: .openCamera)?.absoluteString == "tinycast://command/open-camera")
        check("browser query has no input-free link", CommandDeepLink.url(for: .openInBrowser) == nil)
        check("shell query has no input-free link", CommandDeepLink.url(for: .runShellCommand) == nil)
    }

    static func invalidNativeLinks() {
        for address in [
            "tinycast://command/unknown",
            "tinycast://command",
            "tinycast://command/open-camera/extra",
            "tinycast://command/open-in-browser",
            "tinycast://command/run-shell-command",
            "tinycast://command/search-emoji?query=smile",
            "tinycast://command/open-camera#camera"
        ] {
            let url = URL(string: address)!
            check("invalid route stays with native error handling", CommandDeepLink.claims(url))
            check("invalid native route cannot run: \(address)", CommandDeepLink.parse(url) == nil)
        }
        for address in [
            "https://command/open-camera", "other://command/search-emoji",
            "raycast://command/search-emoji", "tinycast://oauth?code=abc"
        ] {
            let url = URL(string: address)!
            check("unrelated URL is not claimed", !CommandDeepLink.claims(url))
            check("unrelated URL cannot run a native command", CommandDeepLink.parse(url) == nil)
        }
    }

    static func extensionLinks() {
        for address in [
            "tinycast://extensions/thomas/color-picker/pick-color",
            "tinycast://extensions/color-picker/pick-color",
            "raycast://extensions/thomas/color-picker/pick-color",
            "com.raycast:/extensions/thomas/color-picker/pick-color"
        ] {
            let url = URL(string: address)!
            check("extension URL stays with its parser", !CommandDeepLink.claims(url))
            check("extension URL is not a native command", CommandDeepLink.parse(url) == nil)
            let link = ExtensionDeepLink.parse(url: url)
            check("extension URL retains its install", link?.extensionName == "color-picker")
            check("extension URL retains its command", link?.commandName == "pick-color")
        }
        for extensionName in ["thomas/color-picker", "color-picker"] {
            guard let url = ExtensionDeepLink.url(
                extensionName: extensionName, commandName: "pick-color")
            else {
                check("installed command has an address", false)
                continue
            }
            check("copied extension link opens Tinycast", url.scheme == "tinycast")
            let link = ExtensionDeepLink.parse(url: url)
            check("copied extension link retains its install", link?.matches(manifestName: extensionName) == true)
            check("copied extension link retains its command", link?.commandName == "pick-color")
            check("copied extension link has no arguments", link?.arguments == [:])
            check("copied extension link is a user launch", link?.launchType == .userInitiated)
        }
    }
}
