// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A shadow a view drops: its colour, how far it blurs, and how far it sits
/// from the view, x across and y down.
///
///     ColorPicker(.cornflowerBlue)
///         .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
public struct DropShadow: Equatable, Sendable {
    /// The shadow's colour.
    public var color: Color

    /// How far the shadow blurs, in device units.
    public var radius: Double

    /// How far the shadow sits to the right of the view, in device units.
    public var x: Double

    /// How far the shadow sits below the view, in device units.
    public var y: Double

    /// A shadow of `color`, blurred by `radius`, sat `x` across and `y` down.
    public init(color: Color, radius: Double, x: Double = 0, y: Double = 0) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

extension DropShadow: HostRepresentable {
    /// Colour, radius, x, y - a shadow crosses as its four parts.
    public var propValue: PropValue {
        .values([color.propValue, .number(radius), .number(x), .number(y)])
    }

    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard let values = propValue.values, values.count == 4,
              let color = Color(propValue: values[0]),
              let radius = values[1].number, let x = values[2].number, let y = values[3].number
        else { return nil }

        self.init(color: color, radius: radius, x: x, y: y)
    }
}
