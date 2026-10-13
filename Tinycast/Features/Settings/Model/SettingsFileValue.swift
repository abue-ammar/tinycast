import Foundation

/// A value settings.json holds; `nil` from the initializer rejects a value rather than guessing.
protocol SettingsFileValue: Equatable {
    init?(settingsJSON: SettingsFileJSON)
    var settingsJSON: SettingsFileJSON { get }
}

protocol SettingsFileRawValue: SettingsFileValue, RawRepresentable
where RawValue: SettingsFileValue {}

extension SettingsFileRawValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let rawValue = RawValue(settingsJSON: settingsJSON) else { return nil }
        self.init(rawValue: rawValue)
    }

    var settingsJSON: SettingsFileJSON { rawValue.settingsJSON }
}

/// An enum the file spells through its own table, so a sentinel reads as a word.
protocol SettingsFileToken: SettingsFileValue, CaseIterable {
    /// Exhaustive by construction: a new case fails to build until it names its spelling.
    var settingsToken: SettingsFileJSON { get }
}

extension SettingsFileToken {
    init?(settingsJSON: SettingsFileJSON) {
        guard let match = Self.allCases.first(where: { $0.settingsToken == settingsJSON }) else {
            return nil
        }
        self = match
    }

    var settingsJSON: SettingsFileJSON { settingsToken }
}

extension Bool: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let value = settingsJSON.bool else { return nil }
        self = value
    }

    var settingsJSON: SettingsFileJSON { .bool(self) }
}

extension Int: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let value = settingsJSON.int else { return nil }
        self = value
    }

    var settingsJSON: SettingsFileJSON { .number(Double(self)) }
}

extension String: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let value = settingsJSON.string else { return nil }
        self = value
    }

    var settingsJSON: SettingsFileJSON { .string(self) }
}

/// All or nothing: one bad element rejects the list, so a typo never silently shortens it.
extension Array: SettingsFileValue where Element: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        guard let items = settingsJSON.items else { return nil }
        var values: [Element] = []
        values.reserveCapacity(items.count)
        for item in items {
            guard let value = Element(settingsJSON: item) else { return nil }
            values.append(value)
        }
        self = values
    }

    var settingsJSON: SettingsFileJSON { .array(map(\.settingsJSON)) }
}

extension Optional: SettingsFileValue where Wrapped: SettingsFileValue {
    init?(settingsJSON: SettingsFileJSON) {
        if settingsJSON == .null {
            self = .none
            return
        }
        guard let value = Wrapped(settingsJSON: settingsJSON) else { return nil }
        self = .some(value)
    }

    var settingsJSON: SettingsFileJSON { map(\.settingsJSON) ?? .null }
}
