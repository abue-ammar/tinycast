import Foundation

extension Bundle {
    /// The app's channel-aware display name ("Smallcast", "Smallcast Dev", "Smallcast Beta"), driven by CFBundleDisplayName/CFBundleName in the generated Info.plist.
    var appDisplayName: String {
        (object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Smallcast"
    }
}
