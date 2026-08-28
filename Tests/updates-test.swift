import Foundation

@main
@MainActor
struct UpdatesTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        parsesVersions()
        ordersVersions()
        roundTripsVersionsThroughJSON()
        derivesChannels()
        picksNewestForChannel()
        picksTheZipThisMacCanRun()
        rejectsUnusableFeeds()
        offersOnlyWhatIsWorthInstalling()
        keepsOnlyTheChangelog()
        laysOutTheChangelog()
        linksMentionsAndPullRequests()
        blocksWhileBusy()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - AppVersion

    static func parsesVersions() {
        expect(AppVersion("0.2.1")?.description == "0.2.1", "parses a plain triple")
        expect(AppVersion("v0.2.1")?.description == "0.2.1", "strips the tag's leading v")
        expect(AppVersion(" 0.2.1 ")?.description == "0.2.1", "tolerates surrounding whitespace")
        expect(AppVersion("0.2.0-beta.42")?.beta == 42, "reads the beta counter")
        expect(AppVersion("0.2.0-beta.42")?.description == "0.2.0-beta.42", "round-trips a beta")
        expect(AppVersion("0.2.1")?.isPrerelease == false, "a plain triple is not a prerelease")
        expect(AppVersion("0.2.0-beta.1")?.isPrerelease == true, "a beta is a prerelease")

        expect(AppVersion("0.2") == nil, "rejects a two-part version")
        expect(AppVersion("0.2.1.3") == nil, "rejects a four-part version")
        expect(AppVersion("0.2.x") == nil, "rejects a non-numeric field")
        expect(AppVersion("0.2.-1") == nil, "rejects a signed field")
        expect(AppVersion("0.2.0-alpha.1") == nil, "rejects a channel that never ships")
        expect(AppVersion("0.2.0-beta") == nil, "rejects a beta with no counter")
        expect(AppVersion("0.2.0-beta.x") == nil, "rejects a non-numeric beta counter")
        expect(AppVersion("") == nil, "rejects an empty string")
        expect(AppVersion("nightly") == nil, "rejects a name")
    }

    static func ordersVersions() {
        func version(_ text: String) -> AppVersion {
            guard let parsed = AppVersion(text) else {
                fatalError("the ordering cases must all parse — \(text) did not")
            }
            return parsed
        }

        expect(version("1.10.0") > version("1.9.0"), "compares minor numerically, not lexically")
        expect(version("2.0.0") > version("1.99.99"), "major outranks everything below it")
        expect(version("0.2.1") > version("0.2.0"), "patch breaks a tie")
        expect(version("1.0.0") > version("1.0.0-beta.5"), "a release outranks its own prerelease")
        expect(
            version("0.2.0-beta.10") > version("0.2.0-beta.9"),
            "beta counters compare numerically, not lexically")
        expect(version("0.3.0-beta.1") > version("0.2.9"), "a newer triple wins despite being beta")
        expect(version("0.2.1") == version("0.2.1"), "equal triples are equal")
        expect(
            version("0.2.0-beta.1") != version("0.2.0"),
            "a prerelease is never equal to its release")
    }

    static func roundTripsVersionsThroughJSON() {
        guard let original = AppVersion("0.2.0-beta.7"),
            let encoded = try? JSONEncoder().encode(original),
            let decoded = try? JSONDecoder().decode(AppVersion.self, from: encoded)
        else {
            failures += 1
            print("FAIL: a version survives the cache file")
            return
        }
        expect(decoded == original, "a version survives the cache file")
        expect(
            String(bytes: encoded, encoding: .utf8) == "\"0.2.0-beta.7\"",
            "and is stored as a readable string rather than a field bag")
        expect(
            (try? JSONDecoder().decode(AppVersion.self, from: Data("\"junk\"".utf8))) == nil,
            "a corrupt cached version fails to decode instead of defaulting")
    }

    // MARK: - ReleaseChannel

    static func derivesChannels() {
        let stable = ReleaseChannel(bundleID: "com.tinycast.app")
        let beta = ReleaseChannel(bundleID: "com.tinycast.app.beta")
        let dev = ReleaseChannel(bundleID: "com.tinycast.app.dev")

        expect(stable == .stable, "the stable bundle id is the stable channel")
        expect(beta == .beta, "the beta bundle id is the beta channel")
        expect(dev == .development, "the dev bundle id is a local build")
        expect(ReleaseChannel(bundleID: nil) == .development, "a missing bundle id never updates")

        expect(stable.updatesItself && beta.updatesItself, "both shipped channels update")
        expect(!dev.updatesItself, "a local build does not update itself")

        expect(stable.accepts(prerelease: false), "stable takes releases")
        expect(!stable.accepts(prerelease: true), "stable never crosses to a prerelease")
        expect(beta.accepts(prerelease: true), "beta takes prereleases")
        expect(!beta.accepts(prerelease: false), "beta never crosses to a stable release")
        expect(
            !dev.accepts(prerelease: true) && !dev.accepts(prerelease: false),
            "a local build accepts nothing at all")
    }

    // MARK: - ReleaseFeed

    /// Shaped like GitHub's `/releases` payload, down to the snake-cased keys.
    static func feed(_ entries: String...) -> Data {
        Data("[\(entries.joined(separator: ","))]".utf8)
    }

    static func entry(
        tag: String, prerelease: Bool, draft: Bool = false, assets: [String] = ["Tinycast-x.zip"],
        body: String = "Notes."
    ) -> String {
        let list = assets.map {
            """
            {"name":"\($0)","size":1024,
             "browser_download_url":"https://example.invalid/\($0)"}
            """
        }
        return """
            {"tag_name":"\(tag)","prerelease":\(prerelease),"draft":\(draft),
             "body":"\(body)","published_at":"2026-01-05T12:00:00Z",
             "assets":[\(list.joined(separator: ","))]}
            """
    }

    static func picksNewestForChannel() {
        let body = feed(
            entry(tag: "v0.2.0", prerelease: false),
            entry(tag: "v0.3.0", prerelease: false),
            entry(tag: "v0.4.0-beta.1", prerelease: true),
            entry(tag: "v0.4.0-beta.2", prerelease: true))

        let stable = ReleaseFeed.newest(from: body, channel: .stable, architecture: .appleSilicon)
        expect(stable?.version == AppVersion("0.3.0"), "stable takes the newest release")
        expect(stable?.tag == "v0.3.0", "and keeps the tag as published")
        expect(stable?.notes == "Notes.", "and carries the release notes")
        expect(stable?.assetSize == 1024, "and the asset size, for the progress readout")
        expect(
            stable?.assetURL.absoluteString.hasSuffix(".zip") == true,
            "and selects the zip asset")
        expect(stable?.publishedAt != nil, "and parses the ISO-8601 timestamp")

        let beta = ReleaseFeed.newest(from: body, channel: .beta, architecture: .appleSilicon)
        expect(beta?.version == AppVersion("0.4.0-beta.2"), "beta takes the newest prerelease")

        expect(
            ReleaseFeed.newest(from: body, channel: .development, architecture: .appleSilicon) == nil,
            "a local build is offered nothing, however new the feed is")
    }

    static func rejectsUnusableFeeds() {
        expect(
            ReleaseFeed.newest(from: Data(), channel: .stable, architecture: .appleSilicon) == nil,
            "an empty body yields nil")
        expect(
            ReleaseFeed.newest(
                from: Data("not json".utf8), channel: .stable, architecture: .appleSilicon) == nil,
            "a malformed body yields nil rather than throwing")
        expect(
            ReleaseFeed.newest(from: feed(), channel: .stable, architecture: .appleSilicon) == nil,
            "an empty feed yields nil")

        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "v0.3.0", prerelease: false, draft: true)), channel: .stable,
                architecture: .appleSilicon) == nil,
            "a draft is not installable")
        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "v0.3.0", prerelease: false, assets: [])), channel: .stable,
                architecture: .appleSilicon) == nil,
            "a release with no assets is skipped")
        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "v0.3.0", prerelease: false, assets: ["Tinycast-x.dmg"])),
                channel: .stable, architecture: .appleSilicon) == nil,
            "a DMG-only release is not installable, so it is not offered")
        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "nightly", prerelease: false)), channel: .stable,
                architecture: .appleSilicon) == nil,
            "an unparseable tag is skipped")
        expect(
            ReleaseFeed.newest(
                from: feed(entry(tag: "v0.3.0-beta.1", prerelease: false)), channel: .stable,
                architecture: .appleSilicon) == nil,
            "a beta tag flagged as a release is mis-published, not an update")

        let mixed = feed(
            entry(tag: "v0.3.0", prerelease: false), entry(tag: "junk", prerelease: false))
        expect(
            ReleaseFeed.newest(from: mixed, channel: .stable, architecture: .appleSilicon)?.version
                == AppVersion("0.3.0"),
            "one bad entry does not discard the whole feed")
    }

    /// macOS 26 is the last release to boot on Intel, so a stable release carries a thin arm64 zip
    /// and a universal one, and each Mac must be handed a build it can actually launch.
    static func picksTheZipThisMacCanRun() {
        let both = feed(
            entry(
                tag: "v0.3.0", prerelease: false,
                assets: ["Tinycast-0.3.0.zip", "Tinycast-Universal-0.3.0.zip"]))
        expect(
            ReleaseFeed.newest(from: both, channel: .stable, architecture: .intel)?
                .assetURL.absoluteString.contains("-Universal-") == true,
            "Intel takes the universal zip, the only one with an x86_64 slice")
        expect(
            ReleaseFeed.newest(from: both, channel: .stable, architecture: .appleSilicon)?
                .assetURL.absoluteString.contains("-Universal-") == false,
            "Apple silicon prefers the thin zip, and never pays for the Intel slice")

        let thinOnly = feed(entry(tag: "v0.3.0", prerelease: false, assets: ["Tinycast-0.3.0.zip"]))
        expect(
            ReleaseFeed.newest(from: thinOnly, channel: .stable, architecture: .intel) == nil,
            "Intel is offered nothing rather than an arm64 build it cannot launch")

        let universalOnly = feed(
            entry(tag: "v0.3.0", prerelease: false, assets: ["Tinycast-Universal-0.3.0.zip"]))
        expect(
            ReleaseFeed.newest(from: universalOnly, channel: .stable, architecture: .appleSilicon)?
                .version == AppVersion("0.3.0"),
            "Apple silicon falls back to the universal zip when it is the only one published")
    }

    static func offersOnlyWhatIsWorthInstalling() {
        let running = AppVersion("0.2.0")!
        let newer = AvailableRelease(
            version: AppVersion("0.3.0")!, tag: "v0.3.0", notes: "",
            assetURL: URL(string: "https://example.invalid/a.zip")!, assetSize: 1,
            publishedAt: nil)
        let same = AvailableRelease(
            version: running, tag: "v0.2.0", notes: "",
            assetURL: URL(string: "https://example.invalid/a.zip")!, assetSize: 1,
            publishedAt: nil)

        expect(
            ReleaseFeed.offer(newer, running: running, skipped: nil)?.version == newer.version,
            "a newer release is offered")
        expect(
            ReleaseFeed.offer(same, running: running, skipped: nil) == nil,
            "the running version is not an update")
        expect(
            ReleaseFeed.offer(nil, running: running, skipped: nil) == nil,
            "nothing in the feed offers nothing")
        expect(
            ReleaseFeed.offer(newer, running: AppVersion("0.4.0")!, skipped: nil) == nil,
            "an older release never downgrades a newer install")
        expect(
            ReleaseFeed.offer(newer, running: running, skipped: AppVersion("0.3.0")) == nil,
            "a skipped version stays skipped")
        expect(
            ReleaseFeed.offer(newer, running: running, skipped: AppVersion("0.2.5")) != nil,
            "skipping one version does not skip the next one")
    }

    // MARK: - ReleaseNotes

    /// A body as `Scripts/release-notes.sh` composes it.
    static let composedBody = """
        ## What's Changed
        * Adjust top padding in **UpdateWindowView** by @abue-ammar in #304
        * Resolve rmb and renminbi to CNY by @tipybara in #294

        ## New Contributors
        * @tipybara made their first contribution in #294

        \(ReleaseNotes.installMarker)

        **Channel:** beta · **Version:** 0.9.13-beta.61
        Built from 419a5b4. [Full changelog](https://example.invalid/compare)
        """

    static func keepsOnlyTheChangelog() {
        let summary = ReleaseNotes.summary(of: composedBody)
        expect(summary.hasPrefix("## What's Changed"), "the changelog leads the summary")
        expect(summary.hasSuffix("first contribution in #294"), "and the install half is cut away")
        expect(!summary.contains("Homebrew"), "so no install instruction survives the cut")
        expect(!summary.contains(ReleaseNotes.installMarker), "and the marker goes with it")

        expect(
            ReleaseNotes.summary(of: "  Plain notes.\n\n") == "Plain notes.",
            "a body published before the marker existed comes back whole, trimmed")
        expect(ReleaseNotes.summary(of: "") == "", "an empty body stays empty")
        expect(
            ReleaseNotes.summary(of: "\(ReleaseNotes.installMarker)\nOnly install text.") == "",
            "a body that is nothing but install text leaves nothing to show")

        let feedNotes = ReleaseFeed.newest(
            from: feed(
                entry(
                    tag: "v0.3.0", prerelease: false, body: "Changes.\\n\\n<!-- tinycast:install -->\\nBrew.")
            ),
            channel: .stable, architecture: .appleSilicon)?.notes
        expect(feedNotes == "Changes.", "the feed stores the cut summary, so the cache holds it too")
    }

    static func laysOutTheChangelog() {
        let blocks = ReleaseNotes.blocks(from: ReleaseNotes.summary(of: composedBody))
        expect(blocks.count == 5, "five blocks: two headings, three bullets")
        expect(blocks.first == .heading(level: 2, text: "What's Changed"), "a heading loses its hashes")
        expect(
            blocks.dropFirst().first
                == .bullet(
                    "Adjust top padding in **UpdateWindowView** by "
                        + "[@abue-ammar](https://github.com/abue-ammar) in "
                        + "[#304](https://github.com/\(ReleaseFeed.repository)/pull/304)"),
            "a bullet loses its marker, keeps its inline markup, and links its author and PR")
        expect(
            blocks.contains(.heading(level: 2, text: "New Contributors")),
            "the contributors heading survives the blank line before it")

        expect(ReleaseNotes.blocks(from: "").isEmpty, "nothing renders nothing")
        expect(
            ReleaseNotes.blocks(from: "One line.\nStill the same block.")
                == [.paragraph("One line.\nStill the same block.")],
            "a single newline continues a paragraph rather than starting one")
        expect(
            ReleaseNotes.blocks(from: "Before.\n\nAfter.")
                == [.paragraph("Before."), .paragraph("After.")],
            "a blank line separates paragraphs")
        expect(
            ReleaseNotes.blocks(from: "### Fixes") == [.heading(level: 3, text: "Fixes")],
            "a deeper heading keeps its level, so the renderer can size it")
        expect(
            ReleaseNotes.blocks(from: "- dash\n+ plus") == [.bullet("dash"), .bullet("plus")],
            "every Markdown bullet marker is a bullet")
        expect(
            ReleaseNotes.blocks(from: "#hashtag") == [.paragraph("#hashtag")],
            "a hash with no space is text, not a heading")
        expect(
            ReleaseNotes.blocks(from: "2 * 3 = 6") == [.paragraph("2 * 3 = 6")],
            "an asterisk mid-line is not a bullet")
    }

    static func linksMentionsAndPullRequests() {
        func rendered(_ text: String) -> String {
            guard case .bullet(let linked)? = ReleaseNotes.blocks(from: "* \(text)").first else {
                return "not a bullet"
            }
            return linked
        }
        let pull = "https://github.com/\(ReleaseFeed.repository)/pull"

        expect(
            rendered("Fix by @abue-ammar in #304")
                == "Fix by [@abue-ammar](https://github.com/abue-ammar) in [#304](\(pull)/304)",
            "a mention and a PR reference both become links")
        expect(
            rendered("@tipybara made their first contribution in #294")
                == "[@tipybara](https://github.com/tipybara) made their first contribution in [#294](\(pull)/294)",
            "a mention opening the line is linked too")
        expect(
            rendered("track @raycast/api 2.0.3").contains("github.com/raycast") == false,
            "a scoped package name is not a person, so it is left alone")
        expect(
            rendered("mail me at name@example.invalid").contains("github.com/example") == false,
            "an address is not a mention")
        expect(
            rendered("issue #12 and #7") == "issue [#12](\(pull)/12) and [#7](\(pull)/7)",
            "every reference on a line is linked")
        expect(
            rendered("a #hashtag, C# and 0#1") == "a #hashtag, C# and 0#1",
            "a hash without digits, or joined to a word, is not a reference")
        expect(
            rendered("see [#304](\(pull)/304)") == "see [#304](\(pull)/304)",
            "an existing link is left exactly as written")
        expect(
            ReleaseNotes.blocks(from: "## What's Changed") == [.heading(level: 2, text: "What's Changed")],
            "a heading is not linkified")
    }

    // MARK: - UpdateReadiness

    static func blocksWhileBusy() {
        expect(UpdateReadiness.evaluate(UpdateActivity()) == nil, "an idle app is ready to update")

        var busy = UpdateActivity()
        busy.isPaletteVisible = true
        expect(UpdateReadiness.evaluate(busy) == .paletteOpen, "an open palette holds the update")

        busy = UpdateActivity()
        busy.isShowingDialog = true
        expect(UpdateReadiness.evaluate(busy) == .dialogOpen, "an open dialog holds the update")

        busy = UpdateActivity()
        busy.isRecordingHotKey = true
        expect(UpdateReadiness.evaluate(busy) == .recordingHotKey, "a live recorder holds the update")

        busy = UpdateActivity()
        busy.isPromptingForArguments = true
        expect(
            UpdateReadiness.evaluate(busy) == .promptingForArguments,
            "an argument prompt holds the update")

        busy = UpdateActivity()
        busy.isUninstalling = true
        expect(UpdateReadiness.evaluate(busy) == .uninstalling, "a running uninstall holds the update")

        busy = UpdateActivity()
        busy.isRunningExtension = true
        expect(
            UpdateReadiness.evaluate(busy) == .runningExtension,
            "a running extension command holds the update")

        busy = UpdateActivity()
        busy.isExpandingSnippet = true
        expect(
            UpdateReadiness.evaluate(busy) == .expandingSnippet,
            "a snippet mid-expansion holds the update")

        // Everything at once: the report names the one that would lose work, not the topmost panel.
        busy = UpdateActivity()
        busy.isPaletteVisible = true
        busy.isShowingDialog = true
        busy.isExpandingSnippet = true
        expect(
            UpdateReadiness.evaluate(busy) == .expandingSnippet,
            "the costliest interruption is the one reported")

        expect(
            UpdateReadiness.Blocker.expandingSnippet.message.hasSuffix("."),
            "every blocker reads as a sentence the window can show")
    }
}
