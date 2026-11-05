import Foundation
import Security

enum BundleSignature {
    /// Any team, so a new one still updates through the release key, but never an ad-hoc build.
    static let developerID = """
        anchor apple generic \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
        """

    /// Returned so the swap at quit can pin the exact bytes that were verified.
    static func trustedHash(of bundleURL: URL, releaseSigned: Bool) -> Data? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode,
            let requirement = releaseSigned ? compiled(developerID) : runningRequirement,
            SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
        else { return nil }
        return uniqueHash(of: staticCode)
    }

    /// An unsealed bundle can claim any identity, and a nested helper is where one hides.
    private static let flags = SecCSFlags(
        rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)

    private static func compiled(_ text: String) -> SecRequirement? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess
        else { return nil }
        return requirement
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

    private static func uniqueHash(of staticCode: SecStaticCode) -> Data? {
        var information: CFDictionary?
        let options = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, options, &information) == errSecSuccess
        else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
    }
}
