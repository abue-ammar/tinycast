import Foundation

/// The grid the volume commands move on, and how a level reads; CoreAudio is elsewhere.
enum VolumeLevel {
    /// 20 steps of 5%, so every level is round and the presets sit on the grid.
    static let steps = 20
    static let step = 1 / Double(steps)

    static func clamped(_ level: Double) -> Double {
        min(max(level, 0), 1)
    }

    /// `50` or `50%` from a link, as the 0–1 level the runner takes; nil outside 0–100.
    static func level(fromPercent text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
        guard let percent = Double(digits), (0...100).contains(percent) else { return nil }
        return percent / 100
    }

    /// From the nearest line, since a device may store a level slightly off the one it was given.
    static func stepped(_ level: Double, up: Bool) -> Double {
        let line = (clamped(level) * Double(steps)).rounded() + (up ? 1 : -1)
        return clamped(line / Double(steps))
    }

    static func percentage(_ level: Double, locale: Locale) -> String {
        Int((clamped(level) * 100).rounded()).formatted(.percent.locale(locale))
    }

    /// Shared by the HUD and slider, so one level never draws two different icons.
    static func symbol(level: Double, muted: Bool = false) -> String {
        let level = clamped(level)
        if muted || level == 0 { return "speaker.slash.fill" }
        return level < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }
}
