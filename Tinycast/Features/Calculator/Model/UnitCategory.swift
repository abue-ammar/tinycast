import Foundation

enum UnitCategory: String, CaseIterable, Sendable {
    case length, weight, temperature, time, area, volume, digitalStorage
    case angle, speed, pressure, dataRate, acceleration, force, energy, power, frequency
    case electricCurrent, voltage, resistance, electricCharge, volumeFlow
    case pixels, pixelArea, pixelDensity, compound

    var displayName: String {
        switch self {
        case .length: return "Length"
        case .weight: return "Weight"
        case .temperature: return "Temperature"
        case .time: return "Time"
        case .area: return "Area"
        case .volume: return "Volume"
        case .digitalStorage: return "Digital Storage"
        case .angle: return "Angle"
        case .speed: return "Speed"
        case .pressure: return "Pressure"
        case .dataRate: return "Data Transfer Rate"
        case .acceleration: return "Acceleration"
        case .force: return "Force"
        case .energy: return "Energy"
        case .power: return "Power"
        case .frequency: return "Frequency"
        case .electricCurrent: return "Electric Current"
        case .voltage: return "Voltage"
        case .resistance: return "Resistance"
        case .electricCharge: return "Electric Charge"
        case .volumeFlow: return "Volume Flow Rate"
        case .compound: return "Compound Units"
        case .pixels: return "Pixels"
        case .pixelArea: return "Pixel Area"
        case .pixelDensity: return "Pixel Density"
        }
    }

    var dimension: CalcDimension? {
        switch self {
        case .length: return CalcDimension(length: 1)
        case .weight: return CalcDimension(mass: 1)
        case .time: return CalcDimension(time: 1)
        case .area: return CalcDimension(length: 2)
        case .volume: return CalcDimension(length: 3)
        case .digitalStorage: return CalcDimension(data: 1)
        case .speed: return CalcDimension(length: 1, time: -1)
        case .pressure: return CalcDimension(length: -1, mass: 1, time: -2)
        case .dataRate: return CalcDimension(time: -1, data: 1)
        case .acceleration: return CalcDimension(length: 1, time: -2)
        case .force: return CalcDimension(length: 1, mass: 1, time: -2)
        case .energy: return CalcDimension(length: 2, mass: 1, time: -2)
        case .power: return CalcDimension(length: 2, mass: 1, time: -3)
        case .frequency: return CalcDimension(time: -1)
        case .electricCurrent: return CalcDimension(electricCurrent: 1)
        case .voltage: return CalcDimension(length: 2, mass: 1, time: -3, electricCurrent: -1)
        case .resistance: return CalcDimension(length: 2, mass: 1, time: -3, electricCurrent: -2)
        case .electricCharge: return CalcDimension(time: 1, electricCurrent: 1)
        case .volumeFlow: return CalcDimension(length: 3, time: -1)
        case .pixels: return CalcDimension(pixels: 1)
        case .pixelArea: return CalcDimension(pixels: 2)
        case .pixelDensity: return CalcDimension(length: -1, pixels: 1)
        case .temperature, .angle, .compound: return nil
        }
    }
}
