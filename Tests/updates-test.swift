import CryptoKit
import Foundation
import Security

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
        picksTheSignatureBesideItsZip()
        refusesWhatNeitherTrustPathVouchesFor()
        verifiesTheReleaseSignature()
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
        tag: String, prerelease: Bool, draft: Bool = false, assets: [String] = ["Tinycast-x.zip"]
    ) -> String {
        let list = assets.map {
            """
            {"name":"\($0)","size":1024,
             "browser_download_url":"https://example.invalid/\($0)"}
            """
        }
        return """
            {"tag_name":"\(tag)","prerelease":\(prerelease),"draft":\(draft),
             "published_at":"2026-01-05T12:00:00Z",
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

    /// Stable carries a thin arm64 zip and a universal one; each Mac gets what it runs.
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
            version: AppVersion("0.3.0")!, tag: "v0.3.0",
            assetURL: URL(string: "https://example.invalid/a.zip")!, assetSize: 1,
            signatureURL: nil, publishedAt: nil)
        let same = AvailableRelease(
            version: running, tag: "v0.2.0",
            assetURL: URL(string: "https://example.invalid/a.zip")!, assetSize: 1,
            signatureURL: nil, publishedAt: nil)

        expect(
            ReleaseFeed.offer(newer, running: running)?.version == newer.version,
            "a newer release is offered")
        expect(
            ReleaseFeed.offer(same, running: running) == nil,
            "the running version is not an update")
        expect(
            ReleaseFeed.offer(nil, running: running) == nil,
            "nothing in the feed offers nothing")
        expect(
            ReleaseFeed.offer(newer, running: AppVersion("0.4.0")!) == nil,
            "an older release never downgrades a newer install")
    }

    static func picksTheSignatureBesideItsZip() {
        let signed = feed(
            entry(
                tag: "v1.0.0", prerelease: false,
                assets: [
                    "Tinycast-1.0.0.dmg", "Tinycast-1.0.0.zip", "Tinycast-1.0.0.zip.sig",
                    "Tinycast-Universal-1.0.0.zip", "Tinycast-Universal-1.0.0.zip.sig"
                ]))
        expect(
            ReleaseFeed.newest(from: signed, channel: .stable, architecture: .appleSilicon)?
                .signatureURL?.lastPathComponent == "Tinycast-1.0.0.zip.sig",
            "the thin zip carries its own signature")
        expect(
            ReleaseFeed.newest(from: signed, channel: .stable, architecture: .intel)?
                .signatureURL?.lastPathComponent == "Tinycast-Universal-1.0.0.zip.sig",
            "and the universal zip carries the universal one")

        let unsigned = feed(entry(tag: "v1.0.0", prerelease: false, assets: ["Tinycast-1.0.0.zip"]))
        let release = ReleaseFeed.newest(from: unsigned, channel: .stable, architecture: .appleSilicon)
        expect(
            release != nil && release?.signatureURL == nil,
            "a release without a signature is still offered, for the identity path to judge")
    }

    static func refusesWhatNeitherTrustPathVouchesFor() {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(
            BundleSignature.developerID as CFString, [], &requirement)
        expect(
            status == errSecSuccess && requirement != nil,
            "the Developer ID requirement compiles, or the release key would trust nothing")

        let apple = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        expect(
            BundleSignature.trustedHash(of: apple, releaseSigned: true) == nil,
            "the release key alone never trusts a bundle outside Developer ID")
        expect(
            BundleSignature.trustedHash(of: apple, releaseSigned: false) == nil,
            "without the key, a bundle signed by another identity is refused")
        expect(
            BundleSignature.trustedHash(of: URL(fileURLWithPath: "/nonexistent.app"), releaseSigned: true)
                == nil,
            "and nothing is trusted without a seal to check")
    }

    static func verifiesTheReleaseSignature() {
        let key = Curve25519.Signing.PrivateKey()
        let archive = Data("an update archive".utf8)
        guard let raw = try? key.signature(for: archive) else {
            expect(false, "a fresh key signs")
            return
        }
        let signature = Data(raw.base64EncodedString().utf8)
        let verify = { (data: Data, signature: Data, key: Curve25519.Signing.PublicKey) in
            UpdateSignature.isSigned(data, by: signature, key: key)
        }

        expect(verify(archive, signature, key.publicKey), "a matching signature verifies")
        expect(
            verify(archive, signature + Data("\n".utf8), key.publicKey),
            "a trailing newline in the .sig asset is tolerated")
        expect(
            !verify(Data("a tampered archive".utf8), signature, key.publicKey),
            "an altered archive fails")
        expect(
            !verify(archive, signature, Curve25519.Signing.PrivateKey().publicKey),
            "another key fails")
        expect(!verify(archive, Data("not base64".utf8), key.publicKey), "a garbled signature fails")
    }

    // MARK: - UpdateReadiness

    static func blocksWhileBusy() {
        expect(UpdateReadiness.evaluate(UpdateActivity()) == nil, "an idle app can be interrupted")

        var busy = UpdateActivity()
        busy.isPaletteVisible = true
        expect(UpdateReadiness.evaluate(busy) == .paletteOpen, "an open palette blocks an interruption")

        busy = UpdateActivity()
        busy.isShowingDialog = true
        expect(UpdateReadiness.evaluate(busy) == .dialogOpen, "an open dialog blocks an interruption")

        busy = UpdateActivity()
        busy.isRecordingHotKey = true
        expect(UpdateReadiness.evaluate(busy) == .recordingHotKey, "a live recorder blocks an interruption")

        busy = UpdateActivity()
        busy.isUninstalling = true
        expect(UpdateReadiness.evaluate(busy) == .uninstalling, "a running uninstall blocks an interruption")

        busy = UpdateActivity()
        busy.isRunningExtension = true
        expect(
            UpdateReadiness.evaluate(busy) == .runningExtension,
            "a running extension command blocks an interruption")

        busy = UpdateActivity()
        busy.isExpandingSnippet = true
        expect(
            UpdateReadiness.evaluate(busy) == .expandingSnippet,
            "a snippet mid-expansion blocks an interruption")

        // Everything at once: the report names the one that would lose work, not the topmost panel.
        busy = UpdateActivity()
        busy.isPaletteVisible = true
        busy.isShowingDialog = true
        busy.isExpandingSnippet = true
        expect(
            UpdateReadiness.evaluate(busy) == .expandingSnippet,
            "the costliest interruption is the one reported")
    }
}
