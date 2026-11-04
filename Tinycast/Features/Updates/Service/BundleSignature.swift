import Foundation
import Security

/// Sealed, and vouched for by the release key or by the running copy's own signing identity.
enum BundleSignature {
    static func isTrusted(_ bundleURL: URL, releaseSigned: Bool) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else { return false }
        // An unsealed bundle can claim any identity, and a nested helper is where one hides.
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess else { return false }
        if releaseSigned { return true }
        guard let requirement = runningRequirement else { return false }
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
    }

    /// The running copy's own requirement, never a pinned one, so a renewed certificate matches.
    private static var runningRequirement: SecRequirement? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess
        else { return nil }
        return requirement
    }
}
