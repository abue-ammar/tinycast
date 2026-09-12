import Foundation

@main
@MainActor
struct VolumeLevelTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: Double, _ expected: Double, _ message: String) {
        expect(abs(actual - expected) < 1e-9, "\(message) — got \(actual), want \(expected)")
    }

    static func main() {
        expect(VolumeLevel.steps == 20, "the grid is 20 lines")
        expect(VolumeLevel.step, 0.05, "one step is 5%")

        expect(VolumeLevel.clamped(-0.5), 0, "below zero clamps to zero")
        expect(VolumeLevel.clamped(1.5), 1, "above one clamps to one")
        expect(VolumeLevel.clamped(0.42), 0.42, "an in-range level passes through")

        // On-grid levels move exactly one step, in both directions.
        for line in 0...VolumeLevel.steps {
            let level = Double(line) * VolumeLevel.step
            if line < VolumeLevel.steps {
                expect(
                    VolumeLevel.stepped(level, up: true), level + VolumeLevel.step,
                    "up from \(VolumeLevel.percentage(level)) moves one step")
            }
            if line > 0 {
                expect(
                    VolumeLevel.stepped(level, up: false), level - VolumeLevel.step,
                    "down from \(VolumeLevel.percentage(level)) moves one step")
            }
        }

        // Off-grid levels land on the nearest line in the direction of travel, never past it.
        expect(VolumeLevel.stepped(0.37, up: true), 0.40, "up from 37% lands on 40%")
        expect(VolumeLevel.stepped(0.37, up: false), 0.35, "down from 37% lands on 35%")
        expect(VolumeLevel.stepped(0.01, up: false), 0, "down from 1% lands on 0%")
        expect(VolumeLevel.stepped(0.99, up: true), 1, "up from 99% lands on 100%")
        expect(VolumeLevel.stepped(0.021, up: true), 0.05, "a hair above 2% still steps up to 5%")

        // Repeated presses stay on the grid once they reach it.
        var climbing = 0.37
        for expected in [0.40, 0.45, 0.50, 0.55] {
            climbing = VolumeLevel.stepped(climbing, up: true)
            expect(climbing, expected, "climbing from 37% reaches \(Int(expected * 100))%")
        }
        var falling = 0.37
        for expected in [0.35, 0.30, 0.25, 0.20] {
            falling = VolumeLevel.stepped(falling, up: false)
            expect(falling, expected, "falling from 37% reaches \(Int(expected * 100))%")
        }

        // The ends absorb further presses instead of wrapping or overshooting.
        expect(VolumeLevel.stepped(0, up: false), 0, "down at zero stays at zero")
        expect(VolumeLevel.stepped(1, up: true), 1, "up at full stays at full")
        expect(VolumeLevel.stepped(-1, up: false), 0, "an out-of-range low level clamps first")
        expect(VolumeLevel.stepped(2, up: true), 1, "an out-of-range high level clamps first")

        // The preset commands sit on the grid, so a step after one of them is still round.
        for preset in [0, 0.25, 0.5, 0.75, 1.0] {
            let line = preset * Double(VolumeLevel.steps)
            expect(
                line == line.rounded(),
                "the \(VolumeLevel.percentage(preset)) preset is on the grid")
        }

        // Speaker glyph: muted and silent both read as slashed, whatever the underlying level.
        expect(
            VolumeLevel.symbol(level: 0.8, muted: true) == "speaker.slash.fill", "muted is slashed")
        expect(VolumeLevel.symbol(level: 0) == "speaker.slash.fill", "silent is slashed")
        expect(VolumeLevel.symbol(level: 0.05) == "speaker.wave.1.fill", "a low level is one wave")
        expect(VolumeLevel.symbol(level: 0.5) == "speaker.wave.2.fill", "half is two waves")
        expect(VolumeLevel.symbol(level: 1) == "speaker.wave.2.fill", "full stops at two waves")
        expect(
            VolumeLevel.symbol(level: 2) == VolumeLevel.symbol(level: 1),
            "an out-of-range level clamps first")
        // The bands only ever climb, so a rising level can never draw a quieter glyph.
        let bands = stride(from: 0.0, through: 1.0, by: VolumeLevel.step)
            .map { VolumeLevel.symbol(level: $0) }
        expect(
            zip(bands, bands.dropFirst()).allSatisfy { $0 <= $1 },
            "the glyph never steps backwards as the level rises")
        expect(Set(bands).count == 3, "every band is reachable on the step grid")

        expect(VolumeLevel.percentage(0) == "0%", "zero reads 0%")
        expect(VolumeLevel.percentage(0.45) == "45%", "a grid level reads a round number")
        expect(VolumeLevel.percentage(1) == "100%", "full reads 100%")
        expect(VolumeLevel.percentage(1.4) == "100%", "an over-range level reads 100%")
        expect(VolumeLevel.percentage(-0.2) == "0%", "an under-range level reads 0%")
        expect(
            (0...VolumeLevel.steps).allSatisfy {
                !VolumeLevel.percentage(Double($0) * VolumeLevel.step).contains(".")
            },
            "no grid level ever reads as a fraction")

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
