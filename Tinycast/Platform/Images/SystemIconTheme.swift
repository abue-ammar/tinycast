import Foundation

struct SystemIconTheme: Equatable, Sendable {
    enum Material: String, CaseIterable, Sendable {
        case regular = "Regular"
        case clear = "Clear"
        case tinted = "Tinted"
    }

    enum Shade: String, Sendable {
        case light = "Light"
        case dark = "Dark"
        case automatic = "Automatic"
    }

    var material: Material
    var shade: Shade

    static let standard = SystemIconTheme(material: .regular, shade: .light)

    /// No API exposes the style, so read the global default System Settings writes.
    static var current: SystemIconTheme {
        SystemIconTheme(stored: UserDefaults.standard.string(forKey: "AppleIconAppearanceTheme"))
    }

    func isDark(onDarkSurface: Bool) -> Bool {
        shade == .automatic ? onDarkSurface : shade == .dark
    }
}

extension SystemIconTheme {
    init(stored: String?) {
        guard let stored,
            let material = Material.allCases.first(where: { stored.hasPrefix($0.rawValue) }),
            let shade = Shade(rawValue: String(stored.dropFirst(material.rawValue.count)))
        else {
            self = .standard
            return
        }
        self.init(material: material, shade: shade)
    }
}
