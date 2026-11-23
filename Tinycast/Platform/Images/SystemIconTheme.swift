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

    enum Tint: Equatable, Sendable {
        enum Preset: String, Sendable {
            case red = "Red"
            case orange = "Orange"
            case yellow = "Yellow"
            case green = "Green"
            case blue = "Blue"
            case purple = "Purple"
            case pink = "Pink"
            case graphite = "Graphite"
        }

        case accent
        case preset(Preset)
        case custom(red: Double, green: Double, blue: Double, opacity: Double)

        init(stored: String?, custom: String?) {
            if let stored, let preset = Preset(rawValue: stored) {
                self = .preset(preset)
                return
            }
            guard stored == "Other", let custom else {
                self = .accent
                return
            }
            let fields = custom.split(whereSeparator: \.isWhitespace)
            let components = fields.compactMap { Double($0) }
            guard fields.count == 4, components.count == 4,
                components.allSatisfy((0...1).contains)
            else {
                self = .accent
                return
            }
            self = .custom(
                red: components[0], green: components[1], blue: components[2], opacity: components[3])
        }
    }

    let material: Material
    let shade: Shade
    let tint: Tint

    static let standard = SystemIconTheme(material: .regular, shade: .light, tint: .accent)

    /// No API exposes the style, so read the global defaults System Settings writes.
    static var current: SystemIconTheme {
        let defaults = UserDefaults.standard
        return SystemIconTheme(
            stored: defaults.string(forKey: "AppleIconAppearanceTheme"),
            storedTint: defaults.string(forKey: "AppleIconAppearanceTintColor"),
            customTint: defaults.string(forKey: "AppleIconAppearanceCustomTintColor"))
    }

    func isDark(onDarkSurface: Bool) -> Bool {
        shade == .automatic ? onDarkSurface : shade == .dark
    }
}

extension SystemIconTheme {
    init(stored: String?, storedTint: String? = nil, customTint: String? = nil) {
        guard let stored,
            let material = Material.allCases.first(where: { stored.hasPrefix($0.rawValue) }),
            let shade = Shade(rawValue: String(stored.dropFirst(material.rawValue.count)))
        else {
            self = .standard
            return
        }
        self.init(
            material: material, shade: shade,
            tint: material == .tinted ? Tint(stored: storedTint, custom: customTint) : .accent)
    }
}
