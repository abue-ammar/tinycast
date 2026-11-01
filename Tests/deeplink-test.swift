import Foundation

@main
@MainActor
struct DeepLinkTests {
    static var failures = 0
    static var passes = 0
    static let scheme = "tinycast"

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func parse(_ link: String, scheme: String = scheme) -> DeepLink? {
        URL(string: link).flatMap { DeepLink(url: $0, scheme: scheme) }
    }

    static func resolve(_ link: String) -> HotKeyAction? {
        guard case .entry(let action, _)? = parse(link) else { return nil }
        return action
    }

    static func input(_ query: String) -> DeepLinkInput? {
        guard case .entry(_, let input)? = parse("tinycast://command/clipboard-history?" + query)
        else { return nil }
        return input
    }

    static func roundTrip(_ entryID: String) -> HotKeyAction? {
        DeepLink.url(forEntryID: entryID, scheme: scheme).flatMap { url in
            guard case .entry(let action, _)? = DeepLink(url: url, scheme: scheme) else { return nil }
            return action
        }
    }

    static func main() {
        rowChecks()
        entryIDChecks()
        refusalChecks()
        routeChecks()
        inputChecks()
        fieldChecks()
        consentChecks()
        settingsChecks()
        encodingChecks()
        routeInputChecks()
        windowSizeChecks()
        consentKeyChecks()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func rowChecks() {
        for command in CommandID.allCases {
            if let action = command.hotKeyAction {
                expect(roundTrip(command.rawValue) == action, "\(command.rawValue) round-trips")
            } else {
                expect(
                    DeepLink.url(forEntryID: command.rawValue, scheme: scheme) == nil,
                    "\(command.rawValue) has no shortcut, so it has no link")
            }
        }
        for action in SystemActionCatalog.all {
            expect(
                roundTrip(action.entryID) == .systemAction(id: action.id),
                "\(action.entryID) round-trips")
        }
        for command in WindowCommandCatalog.all {
            expect(
                roundTrip(command.entryID) == .windowCommand(id: command.id),
                "\(command.entryID) round-trips")
        }

        let id = UUID()
        let uuid = id.uuidString.lowercased()
        for (entryID, action) in storedRows(id: id, uuid: uuid) {
            expect(roundTrip(entryID) == action, "\(entryID) round-trips")
        }
        let snippet = "/Users/me/Snippets/Sign off ✍️.md"
        expect(
            roundTrip(StoredSnippet.entryIDPrefix + snippet) == .snippet(id: snippet),
            "a snippet's file path survives percent-encoding")

        expect(
            DeepLink.url(forEntryID: "command:clipboard-history", scheme: scheme)?.absoluteString
                == "tinycast://command/clipboard-history",
            "a command's link reads as its entry ID")
        expect(
            DeepLink.url(forEntryID: "window-command:left-half", scheme: "tinycast-dev")?
                .absoluteString == "tinycast-dev://window-command/left-half",
            "a link is built in the scheme it is given")
        expect(
            resolve("TINYCAST://Window-Command/left-half") == .windowCommand(id: .leftHalf),
            "scheme and kind are case-insensitive")
        expect(
            resolve("tinycast://quicklink/\(id.uuidString.uppercased())") == .quicklink(id: id),
            "an uppercase UUID still resolves")
    }

    static func storedRows(id: UUID, uuid: String) -> [(String, HotKeyAction)] {
        [
            (CustomWindowSize.entryIDPrefix + uuid, .customWindowSize(id: id)),
            (WindowLayout.entryIDPrefix + uuid, .windowLayout(id: id)),
            (Room.entryIDPrefix + uuid, .windowRoom(id: id)),
            (CustomQuickAction.entryIDPrefix + uuid, .quickAction(id: id)),
            (CustomCommand.entryIDPrefix + uuid, .customCommand(id: id)),
            (Quicklink.entryIDPrefix + uuid, .quicklink(id: id)),
            (AppleShortcut.entryIDPrefix + uuid, .appleShortcut(id: id))
        ]
    }

    static func entryIDChecks() {
        let id = UUID()
        for (entryID, action) in storedRows(id: id, uuid: id.uuidString.lowercased()) {
            expect(action.entryID == entryID, "\(entryID) is what its action names")
        }
        var actions = CommandID.allCases.compactMap(\.hotKeyAction)
        actions += SystemAction.ID.allCases.map { .systemAction(id: $0) }
        actions += WindowCommand.ID.allCases.map { .windowCommand(id: $0) }
        actions.append(.snippet(id: "/Users/me/Snippets/a.md"))
        for action in actions {
            expect(
                action.entryID.flatMap(HotKeyAction.init(entryID:)) == action,
                "\(action.defaultsKey) names an entry ID that parses back to it")
        }
        let unnamed: [HotKeyAction] = [
            .togglePalette, .dictation, .app(bundleID: "com.apple.Safari"),
            .settingsPane(bundleID: "com.apple.Wallpaper-Settings.extension"),
            .extensionCommand(entryID: "extension:demo/search"), .command(.quit)
        ]
        for action in unnamed {
            expect(action.entryID == nil, "\(action.defaultsKey) has no entry ID, so no link")
        }
    }

    static func refusalChecks() {
        expect(
            DeepLink.url(forEntryID: "/Applications/Safari.app", scheme: scheme) == nil,
            "apps have no link")
        expect(
            DeepLink.url(forEntryID: "command:nope", scheme: scheme) == nil,
            "an unknown command has no link")
        expect(
            DeepLink.url(forEntryID: "extension:demo/search", scheme: scheme) == nil,
            "extension commands keep their own link")
        expect(parse("raycast://command/clipboard-history") == nil, "built-in links are Tinycast's alone")
        expect(
            parse("tinycast-dev://command/clipboard-history") == nil,
            "another channel's scheme is not this build's")
        expect(
            parse("tinycast://command/clipboard-history", scheme: "tinycast-dev") == nil,
            "a Debug build ignores Release's links")
        expect(
            parse("tinycast://extensions/demo/search") == nil,
            "extension links fall through to their own router")
        expect(
            parse("tinycast://extensions/owner/demo/search?arguments=%7B%7D") == nil,
            "an extension link with input still falls through")
        expect(resolve("tinycast://command") == nil, "a kind without an ID is not a command")
        expect(resolve("tinycast://command/") == nil, "an empty ID is not a command")
        expect(resolve("tinycast://command/nope") == nil, "an unknown command does not resolve")
    }

    static func routeChecks() {
        expect(parse("tinycast://") == .launcher(fallbackText: nil), "the bare scheme opens the launcher")
        expect(
            parse("tinycast://search?fallbackText=2%2B2") == .launcher(fallbackText: "2+2"),
            "search carries its text into the launcher")
        expect(parse("tinycast://search/more") == nil, "search takes no path")
        expect(
            parse("tinycast://settings/Permissions") == .settings(slug: "permissions"),
            "a settings link names its tab, case-insensitively")
        expect(parse("tinycast://settings") == nil, "a settings link without a tab is refused")
        expect(parse("tinycast://settings/ai/providers") == nil, "a settings tab is one segment")
        expect(
            parse("tinycast://command/clipboard-history") == .entry(.command(.clipboardHistory), .none),
            "a link without parameters carries no input")
    }

    static func inputChecks() {
        expect(
            input("fallbackText=caf%C3%A9%20%F0%9F%98%80")?.fallbackText == "café 😀",
            "fallbackText is percent-decoded")
        expect(
            input("FALLBACKTEXT=hi")?.fallbackText == "hi",
            "parameter names are case-insensitive")
        expect(input("fallbackText=")?.isEmpty == true, "an empty value is no input")
        expect(input("launchType=background")?.isEmpty == true, "an unknown parameter is ignored")
        expect(
            input("arguments=%7B%22Query%22%3A%22rust%22%7D")?.arguments
                == .named(["Query": "rust"]),
            "a JSON object names its arguments")
        expect(
            input("arguments=%5B%22a%22%2C%22b%22%5D")?.arguments == .positional(["a", "b"]),
            "a JSON array gives arguments in order")
        expect(
            input("arguments=%7B%22n%22%3A3%2C%22x%22%3A1.5%2C%22b%22%3Atrue%2C%22z%22%3Anull%7D")?
                .arguments == .named(["n": "3", "x": "1.5", "b": "true", "z": ""]),
            "numbers, booleans and null become the text a field would hold")
        expect(
            input("context=%7B%22name%22%3A%22Docs%22%7D")?.context == .fields(["name": "Docs"]),
            "context is a JSON object")
        expect(input("arguments=nope") == nil, "malformed arguments refuse the link")
        expect(input("arguments=%7B%22a%22%3A%7B%7D%7D") == nil, "a nested value refuses the link")
        expect(
            input("context=%5B%7B%22name%22%3A%22A%22%7D%2C%7B%22name%22%3A%22B%22%7D%5D")?.context
                == .list([["name": "A"], ["name": "B"]]),
            "a list of objects is a batch")
        expect(input("context=%5B%22a%22%5D") == nil, "a list of anything else refuses the link")
        expect(input("context=%5B%7B%22a%22%3A%5B%5D%7D%5D") == nil, "a nested value in a batch refuses it")
        let marks = "a" + String(repeating: "\u{301}", count: DeepLinkInput.maximumParameterBytes)
        expect(
            DeepLinkInput(queryItems: [URLQueryItem(name: "fallbackText", value: marks)]) == nil,
            "the cap counts bytes, so combining marks can't hide inside one character")
        let oversized = String(repeating: "a", count: DeepLinkInput.maximumParameterBytes + 1)
        expect(input("fallbackText=" + oversized) == nil, "an oversized parameter refuses the link")
    }

    static func fieldChecks() {
        let names = ["Branch", "Message", "Branch"]
        let position: (Int) -> String = { "$\($0 + 1)" }
        let positional = DeepLinkInput(
            fallbackText: "ignored", arguments: .positional(["main", "fix", "x", "extra"]), context: nil)
        expect(
            positional.fieldValues(names: names, fieldID: position)
                == ["$1": "main", "$2": "fix", "$3": "x"],
            "positional values fill fields in order and extras are dropped")
        let named = DeepLinkInput(
            fallbackText: nil, arguments: .named(["Branch": "main", "Other": "y"]), context: nil)
        expect(
            named.fieldValues(names: names, fieldID: position) == ["$1": "main"],
            "a named value fills only the first field of that name")
        let text = DeepLinkInput(fallbackText: "rust", arguments: nil, context: nil)
        let quicklinkNames = ["Query", "Site"]
        expect(
            text.fieldValues(names: quicklinkNames, fieldID: { quicklinkNames[$0] })
                == ["Query": "rust"],
            "with no arguments, fallbackText fills the first field")
        expect(
            DeepLinkInput.none.fieldValues(names: names, fieldID: position).isEmpty,
            "no input fills nothing")
    }

    static func settingsChecks() {
        let slugs = SettingsTab.allCases.map(\.slug)
        expect(Set(slugs).count == slugs.count, "every Settings tab has a slug of its own")
        for tab in SettingsTab.allCases {
            expect(SettingsTab(slug: tab.slug) == tab, "settings/\(tab.slug) opens its own tab")
        }
        expect(SettingsTab(slug: "nope") == nil, "an unknown tab opens nothing")
    }

    static func encodingChecks() {
        let entryID = "command:search-files"
        let inputs: [DeepLinkInput] = [
            DeepLinkInput(fallbackText: "a & b = c + d # é 😀 %20", arguments: nil, context: nil),
            DeepLinkInput(fallbackText: nil, arguments: .named(["Query": "x/y?z", "Site": ""]), context: nil),
            DeepLinkInput(fallbackText: nil, arguments: .positional(["a", "", "c"]), context: nil),
            DeepLinkInput(
                fallbackText: nil, arguments: nil,
                context: .fields(["name": "Docs", "link": "https://a.b/?q=1"])),
            DeepLinkInput(fallbackText: "t", arguments: nil, context: .list([["name": "A"], ["name": "B"]]))
        ]
        for original in inputs {
            let url = DeepLink.url(forEntryID: entryID, scheme: scheme, input: original)
            let parsed = url.flatMap { DeepLink(url: $0, scheme: scheme) }
            expect(
                parsed == .entry(.command(.searchFiles), original),
                "\(url?.absoluteString ?? "nil") reads back as the input it was built from")
        }
        expect(
            DeepLink.url(forEntryID: entryID, scheme: scheme)?.query == nil,
            "a link with no input has no query")
        expect(
            DeepLinkInput(fallbackText: nil, arguments: .named(["q": "rust"]), context: nil).summary
                == #"{"q":"rust"}"#,
            "a summary shows the input as it was sent")
        let long = DeepLinkInput(
            fallbackText: String(repeating: "x", count: 500), arguments: nil, context: nil)
        expect(long.summary.count == 161 && long.summary.hasSuffix("…"), "a long summary is cut")
    }

    static func routeInputChecks() {
        let note = "Groceries & plans?.md"
        expect(
            DeepLink.url(forNote: note, scheme: scheme).flatMap { DeepLink(url: $0, scheme: scheme) }
                == .note(name: note),
            "a note's link reads back as its file name")
        expect(parse("tinycast://note/a/b.md") == nil, "a note name is one segment")
        let chat = UUID()
        expect(
            DeepLink.url(forChat: chat, scheme: scheme).flatMap { DeepLink(url: $0, scheme: scheme) }
                == .chat(id: chat),
            "a chat's link reads back as its ID")
        expect(parse("tinycast://chat/nope") == nil, "a chat link needs a UUID")
        expect(
            parse("tinycast://system-action/set-volume?fallbackText=40")
                == .entry(
                    .systemAction(id: .setVolume),
                    DeepLinkInput(fallbackText: "40", arguments: nil, context: nil)),
            "set-volume carries its level as input")
        expect(
            DeepLinkSource.outside.mayRun(.quicklink(id: chat)), "a link from outside may open a quicklink")
        expect(!DeepLinkSource.tinycast.mayRun(.quicklink(id: chat)), "a quicklink may not open a quicklink")
        expect(
            DeepLinkSource.tinycast.mayRun(.command(.searchFiles)),
            "a quicklink may open anything else")
    }

    static func windowSizeChecks() {
        let base = "tinycast://window-size?arguments="
        let json = #"{"width":"1200","height":"60%","anchor":"top-left","x":"10","y":"-20"}"#
        let encoded = json.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard case .windowSize(let size)? = parse(base + encoded) else {
            return expect(false, "a window-size link with a size parses")
        }
        expect(size.width == .init(1200, .points), "a bare width is points")
        expect(size.height == .init(60, .percent), "a % height is a share of the screen")
        expect(size.anchor == .topLeft && size.offset == .init(x: 10, y: -20), "anchor and offset apply")
        let fields: [String: String] = ["width": "800", "height": "600"]
        let plain = CustomWindowSize(linkFields: fields)
        expect(plain?.anchor == .center && plain?.offset == .zero, "anchor and offset default")
        for (field, value) in [
            ("width", "0"), ("width", "101%"), ("height", "big"), ("anchor", "middle"), ("x", "5000")
        ] {
            var bad = fields
            bad[field] = value
            expect(CustomWindowSize(linkFields: bad) == nil, "\(field)=\(value) is refused, not clamped")
        }
        expect(CustomWindowSize(linkFields: ["width": "800"]) == nil, "a size needs both sides")
        expect(parse("tinycast://window-size") == nil, "a window-size link with no size is refused")
    }

    static func consentKeyChecks() {
        let plain = DeepLinkInput.none
        let text = DeepLinkInput(fallbackText: "~/Downloads/", arguments: nil, context: nil)
        expect(
            !DeepLinkConsentPolicy.requiresConsent(.command(.searchFiles), input: plain),
            "a screen with no input never asks")
        expect(
            DeepLinkConsentPolicy.requiresConsent(.command(.searchFiles), input: text),
            "any input asks, since a page chose it")
        let entryID = "snippet:/Users/me/What?.md"
        let keyed = DeepLinkConsentPolicy.key(entryID: entryID, input: text)
        expect(
            keyed != DeepLinkConsentPolicy.key(entryID: entryID, input: plain),
            "a grant with input never covers the row without it")
        expect(
            keyed
                != DeepLinkConsentPolicy.key(
                    entryID: entryID, input: DeepLinkInput(fallbackText: "~/", arguments: nil, context: nil)),
            "a grant covers only its exact input")
        let parts = DeepLinkConsentPolicy.parts(ofKey: keyed)
        expect(parts?.entryID == entryID && parts?.input == text, "a key reads back, even with ? in a path")
        expect(
            DeepLinkConsentPolicy.parts(ofKey: "system-action:lock-screen")?.input == plain,
            "a plain key is the row alone")
    }

    static func consentChecks() {
        expect(
            !DeepLinkConsentPolicy.requiresConsent(.command(.clipboardHistory)),
            "opening a Tinycast screen runs without asking")
        expect(
            !DeepLinkConsentPolicy.requiresConsent(.command(.createQuicklink)),
            "a create editor saves nothing on its own, so it runs without asking")
        expect(
            DeepLinkConsentPolicy.requiresConsent(.command(.pasteSequentially)),
            "pasting into another app asks first")
        expect(
            DeepLinkConsentPolicy.requiresConsent(.command(.openCamera)),
            "turning the camera on asks first")
        expect(
            DeepLinkConsentPolicy.requiresConsent(.windowCommand(id: .leftHalf)),
            "moving another app's window asks first")
        expect(
            DeepLinkConsentPolicy.requiresConsent(.customCommand(id: UUID())),
            "running a script asks first")
    }
}
