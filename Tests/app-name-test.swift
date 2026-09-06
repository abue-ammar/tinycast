import Foundation

@main
struct AppNameTest {
    static func main() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("tinycast-app-name-\(UUID().uuidString)")

        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        /// A real bundle on disk: `installedAppName` reads the plist the way the scan does.
        func makeApp(_ fileName: String, info: [String: Any]) -> Bundle? {
            let url = root.appendingPathComponent(fileName)
            let contents = url.appendingPathComponent("Contents")
            try? fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try? PropertyListSerialization.data(
                fromPropertyList: info, format: .xml, options: 0)
            try? data?.write(to: contents.appendingPathComponent("Info.plist"))
            return Bundle(url: url)
        }

        check(
            "a blank display name is not a name",
            AppDisplayName.named("") == nil && AppDisplayName.named("   ") == nil
                && AppDisplayName.named("\n\t") == nil)
        check("a missing value is not a name", AppDisplayName.named(nil) == nil)
        check("a non-string value is not a name", AppDisplayName.named(42) == nil)
        check("a name is trimmed", AppDisplayName.named("  Paw  ") == "Paw")

        check(
            "a blank display name falls back to CFBundleName",
            AppDisplayName.inInfo(["CFBundleDisplayName": "", "CFBundleName": "RapidAPI"])
                == "RapidAPI")
        check(
            "a present display name still wins",
            AppDisplayName.inInfo(["CFBundleDisplayName": "Shown", "CFBundleName": "Internal"])
                == "Shown")
        check(
            "an info dictionary naming nothing yields nil",
            AppDisplayName.inInfo(["CFBundleDisplayName": " ", "CFBundleName": ""]) == nil)
        // Image Playground's loctable ships both, and CFBundle reads the platform-suffixed one.
        check(
            "the macOS variant of a key wins over the bare key",
            AppDisplayName.inInfo([
                "CFBundleDisplayName-macos": "Image Playground",
                "CFBundleDisplayName": "Playground", "CFBundleName": "Image Playground"
            ]) == "Image Playground")
        check(
            "a blank macOS variant falls through to the bare key",
            AppDisplayName.inInfo([
                "CFBundleDisplayName-macos": "", "CFBundleDisplayName": "Playground"
            ]) == "Playground")
        check(
            "a macOS variant of CFBundleName still loses to a real display name",
            AppDisplayName.inInfo([
                "CFBundleDisplayName": "Shown", "CFBundleName-macos": "Internal"
            ]) == "Shown")

        // RapidAPI 4.5.5 ships exactly this: blank display name, real `CFBundleName`, Paw's old id.
        let rapidAPI = makeApp(
            "RapidAPI.app",
            info: [
                "CFBundleDisplayName": "", "CFBundleName": "RapidAPI",
                "CFBundleIdentifier": "com.luckymarmot.Paw"
            ])
        check(
            "a bundle with a blank display name is named by CFBundleName",
            rapidAPI?.installedAppName == "RapidAPI")

        let unnamed = makeApp("Mystery.app", info: ["CFBundleIdentifier": "com.example.mystery"])
        check(
            "a bundle naming itself nowhere falls back to its filename",
            unnamed?.installedAppName == "Mystery")

        let blankBoth = makeApp(
            "Ghost.app",
            info: [
                "CFBundleDisplayName": "  ", "CFBundleName": "",
                "CFBundleIdentifier": "com.example.ghost"
            ])
        check(
            "two blank keys still fall back to the filename",
            blankBoth?.installedAppName == "Ghost")

        func codes(_ preferred: [String]) -> [String] {
            BundleLocalization.indexedLanguages(preferred)
        }
        check(
            "a Simplified Chinese Mac looks up the zh_CN Apple actually keys by",
            codes(["zh-Hans-CN"]).contains("zh_CN"))
        check(
            "a script-only tag maximizes to reach the same key",
            codes(["zh-Hans"]).contains("zh_CN"))
        check(
            "Traditional Chinese resolves to its own region, not the mainland's",
            codes(["zh-Hant-TW"]).contains("zh_TW") && !codes(["zh-Hant-TW"]).contains("zh_CN"))
        check(
            "English stays last so a Chinese reader still types \"Calendar\"",
            codes(["zh-Hans-CN"]).last == "en")
        check(
            "a tag carrying no script is left exactly as it was",
            codes(["pt-BR"]) == ["pt-BR", "pt_BR", "pt", "en"])

        /// The whole path: a bundle translated only in its loctable, read as the scan reads it.
        func makeLocalizedApp(_ fileName: String, table: [String: Any]) -> URL {
            let url = root.appendingPathComponent(fileName)
            let resources = url.appendingPathComponent("Contents/Resources")
            try? fm.createDirectory(at: resources, withIntermediateDirectories: true)
            let data = try? PropertyListSerialization.data(
                fromPropertyList: table, format: .xml, options: 0)
            try? data?.write(to: resources.appendingPathComponent("InfoPlist.loctable"))
            return url
        }

        let monitor = makeLocalizedApp(
            "Activity Monitor.app",
            table: [
                "zh_CN": ["CFBundleName": "活动监视器"],
                "zh_TW": ["CFBundleName": "活動監視器"],
                "en": ["CFBundleName": "Activity Monitor"]
            ])
        check(
            "a loctable app is found by its Chinese name, English still indexed",
            BundleLocalization.names(for: monitor, languages: codes(["zh-Hans-CN"]))
                == ["活动监视器", "Activity Monitor"])
        check(
            "an English Mac indexes only the English name",
            BundleLocalization.names(for: monitor, languages: codes(["en-US"]))
                == ["Activity Monitor"])

        try? fm.removeItem(at: root)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
