import Foundation

struct ClipboardSource: Sendable {
    let bundleIDs: [String]

    var bundleID: String? { bundleIDs.first }

    func isDisabled(in disabledApps: Set<String>, explicitBundleID: String?) -> Bool {
        bundleIDs.contains(where: disabledApps.contains)
            || explicitBundleID.map(disabledApps.contains) == true
    }
}
