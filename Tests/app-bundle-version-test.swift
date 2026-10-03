import Foundation

@main
struct AppBundleVersionTest {
    static func main() {
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                failures += 1
                print("FAIL  \(description)")
            }
        }

        /// A version string orders against another, or is unreadable and never outranks.
        func newer(_ lhs: String, than rhs: String) -> Bool {
            guard let left = AppBundleVersion(lhs), let right = AppBundleVersion(rhs)
            else { return false }
            return left > right
        }

        /// The launcher keeps one entry per bundle id, so the newest version has to win
        /// regardless of which copy the filesystem enumerated first.
        func newestWins() {
            check("27.0 beats 26.6", newer("27.0", than: "26.6"))
            check("26.6 beats 9.4: components compare as numbers", newer("26.6", than: "9.4"))
            check("and the reverse is false", !newer("9.4", than: "26.6"))
            check("a two-component version still orders", newer("2025.3", than: "2025.1"))
            // Regression guard: a lexicographic comparison of the same numbers gets this
            // pair backwards, because "26.6" sorts above "9.4" as text.
            check("26.6 outranks 9.4, which text ordering gets backwards", newer("26.6", than: "9.4"))
            check("patch level orders", newer("1.0.1", than: "1.0.0"))
            check("equal versions are not newer", !newer("1.0", than: "1.0"))
        }

        /// A beta sits beside its release, and the release is the one to launch.
        func prereleaseRanksBelowItsRelease() {
            check("27.0 beats 27.0-beta.3", newer("27.0", than: "27.0-beta.3"))
            check("a beta never beats its release", !newer("27.0-beta.3", than: "27.0"))
            check(
                "beta numbers order among themselves",
                newer("27.0-beta.4", than: "27.0-beta.3"))
            // Numbers decide before anything else, so a 27 beta outranks a shipped 26.
            // Preferring stable over a newer beta is a product policy and deliberately
            // not encoded here; the caller would add it, not this type.
            check(
                "numbers decide first: a 27 beta outranks a shipped 26",
                newer("27.0-beta.3", than: "26.0"))
            check("and the reverse is false", !newer("26.0", than: "27.0-beta.3"))
            check(
                "an unreadable channel leaves the pair tied",
                !newer("27.0-alpha.1", than: "27.0-beta.3"))
        }

        /// An unreadable version must not silently win, or a bundle with no version string
        /// would displace a real install on every scan.
        func unreadableNeverWins() {
            check("an absent version never beats a real one", !newer("", than: "27.0"))
            check("and a real one does not lose to an absent", !newer("27.0", than: ""))
            check("an empty string is unreadable", AppBundleVersion("") == nil)
            check("a bare channel is unreadable", AppBundleVersion("beta") == nil)
            check(
                "an unreadable incumbent is not displaced",
                !newer("27.0", than: "beta"))
        }

        newestWins()
        prereleaseRanksBelowItsRelease()
        unreadableNeverWins()

        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
    }
}