import Foundation

extension LocalizedStringResource {
    /// `String(localized:)` on a resource can bypass the bundle's table cache and reparse every call.
    func resolved() -> String {
        guard let source = bundle.loaded else { return String(localized: self) }
        let value = source.localizedString(forKey: key, value: nil, table: table)
        let needsArguments = value.contains("%")
        let needsDefault = value == key && defaultValue != String.LocalizationValue(key)
        return needsArguments || needsDefault ? String(localized: self) : value
    }
}

extension LocalizedStringResource.BundleDescription {
    fileprivate var loaded: Bundle? {
        switch self {
        case .main: .main
        case .forClass(let type): Bundle(for: type)
        case .atURL(let url): Bundle(url: url)
        @unknown default: nil
        }
    }
}
