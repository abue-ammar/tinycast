import Foundation

enum UnitCategory: String, CaseIterable, Sendable {
    case length, weight, temperature, time, area, volume, digitalStorage
    case angle, speed, pressure, dataRate, acceleration, force, energy, power, frequency
    case electricCurrent, voltage, resistance, electricCharge, volumeFlow
    case fuelEconomy, fuelConsumption
    case pixels, pixelArea, pixelDensity, compound

    var displayName: String {
        switch self {
        case .length: return String(localized: "Length")
        case .weight: return String(localized: "Weight")
        case .temperature: return String(localized: "Temperature")
        case .time: return String(localized: "unit-category-time", defaultValue: "Time")
        case .area: return String(localized: "Area")
        case .volume: return String(localized: "Volume")
        case .digitalStorage: return String(localized: "Digital Storage")
        case .angle: return String(localized: "Angle")
        case .speed: return String(localized: "Speed")
        case .pressure: return String(localized: "Pressure")
        case .dataRate: return String(localized: "Data Transfer Rate")
        case .acceleration: return String(localized: "Acceleration")
        case .force: return String(localized: "Force")
        case .energy: return String(localized: "Energy")
        case .power: return String(localized: "Power")
        case .frequency: return String(localized: "Frequency")
        case .electricCurrent: return String(localized: "Electric Current")
        case .voltage: return String(localized: "Voltage")
        case .resistance: return String(localized: "Resistance")
        case .electricCharge: return String(localized: "Electric Charge")
        case .volumeFlow: return String(localized: "Volume Flow Rate")
        case .fuelEconomy: return String(localized: "Fuel Economy")
        case .fuelConsumption: return String(localized: "Fuel Consumption")
        case .compound: return String(localized: "Compound Units")
        case .pixels: return String(localized: "Pixels")
        case .pixelArea: return String(localized: "Pixel Area")
        case .pixelDensity: return String(localized: "Pixel Density")
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
        case .fuelEconomy: return CalcDimension(length: -2)
        case .fuelConsumption: return CalcDimension(length: 2)
        case .pixels: return CalcDimension(pixels: 1)
        case .pixelArea: return CalcDimension(pixels: 2)
        case .pixelDensity: return CalcDimension(length: -1, pixels: 1)
        case .temperature, .angle, .compound: return nil
        }
    }
}
