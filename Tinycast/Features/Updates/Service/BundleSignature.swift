import Foundation
import Security

enum BundleSignature {
    static func isTrusted(_ bundleURL: URL, releaseSigned: Bool) -> Bool {
        guard let code = sealedCode(at: bundleURL) else { return false }
        if releaseSigned { return true }
        guard let requirement = runningRequirement else { return false }
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    static func isSealed(_ bundleURL: URL) -> Bool {
        sealedCode(at: bundleURL) != nil
    }

    /// An unsealed bundle can claim any identity, and a nested helper is where one hides.
    private static let flags = SecCSFlags(
        rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)

    private static func sealedCode(at bundleURL: URL) -> SecStaticCode? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode, SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess
        else { return nil }
        return staticCode
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
