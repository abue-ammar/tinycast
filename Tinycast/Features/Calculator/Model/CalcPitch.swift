import Foundation

/// Equal-tempered pitch against frequency, A4 at 440 Hz: `440 hz to pitch` is A4, `c4 to hz` 261.6 Hz.
enum CalcPitch {
    static func evaluate(_ tokens: [CalcToken], query: String) -> CalcResult? {
        guard tokens.count >= 3, CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let target) = tokens.last
        else { return nil }
        if target == "pitch" || target == "note" { return pitch(of: Array(tokens.dropLast(2)), query: query) }
        guard tokens.count == 3, case .ident(let name) = tokens[0], let midi = midiNumber(name),
            let unit = CalcUnits.byName[target], unit.category == .frequency
        else { return nil }
        let hertz = 440 * pow(2, (midi - 69) / 12)
        return .phrase(query, .measurement(hertz / unit.factor, unit: unit), target: unit.name)
    }

    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    private static func pitch(of source: [CalcToken], query: String) -> CalcResult? {
        guard let value = CalcExpressionParser.value(source), case .unit(let unit) = value.kind,
            unit.category == .frequency
        else { return nil }
        let hertz = value.amount * unit.factor
        guard hertz > 0 else { return nil }
        let midi = (69 + 12 * log2(hertz / 440)).rounded()
        guard midi.isFinite, (0...127).contains(midi) else { return nil }
        let index = Int(midi)
        let text = names[index % 12] + String(index / 12 - 1)
        return .phrase(
            query, .value(display: text, copyText: text), target: String(localized: "Pitch"), canChain: false)
    }

    /// `a4`, `c-1`, `bb3`: a natural or flat note and its octave, as the MIDI number it names.
    private static func midiNumber(_ name: String) -> Double? {
        var rest = Substring(name.lowercased())
        guard let letter = rest.first,
            let step = ["c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11][letter]
        else { return nil }
        rest.removeFirst()
        var semitone = step
        if rest.first == "b", rest.count > 1 {
            semitone -= 1
            rest.removeFirst()
        }
        guard let octave = Int(rest), (-1...9).contains(octave) else { return nil }
        let midi = Double((octave + 1) * 12 + semitone)
        return (0...127).contains(midi) ? midi : nil
    }
}
