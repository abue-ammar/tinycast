struct CalcDimension: Hashable, Sendable {
    var length = 0.0
    var mass = 0.0
    var time = 0.0
    var data = 0.0

    static let scalar = CalcDimension()

    func adding(_ other: Self, scale: Double = 1) -> Self {
        Self(
            length: length + other.length * scale, mass: mass + other.mass * scale,
            time: time + other.time * scale, data: data + other.data * scale)
    }

    func raised(to power: Double) -> Self {
        Self(length: length * power, mass: mass * power, time: time * power, data: data * power)
    }
}
