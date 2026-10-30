// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A turn, in degrees or in radians - the value `.rotationEffect` and
/// `.rotation3DEffect` take.
///
///     Image(icon).rotationEffect(.degrees(45))
///     Image(icon).rotationEffect(45)         // a literal is degrees
public struct Angle: Equatable, Sendable, HostRepresentable {
    /// The turn, in degrees.
    public var degrees: Double

    /// The same turn, in radians.
    public var radians: Double {
        get { degrees * .pi / 180 }
        set { degrees = newValue * 180 / .pi }
    }

    /// No turn.
    public static let zero = Angle(radians: 0)

    /// A turn of that many degrees.
    public init(degrees: Double) {
        self.degrees = degrees
    }

    /// A turn of that many radians.
    public init(radians: Double) {
        degrees = radians * 180 / .pi
    }

    /// A turn of that many degrees.
    public static func degrees(_ degrees: Double) -> Angle {
        Angle(degrees: degrees)
    }

    /// A turn of that many radians.
    public static func radians(_ radians: Double) -> Angle {
        Angle(radians: radians)
    }

    /// As a host is handed it: the degrees.
    public var propValue: PropValue { .number(degrees) }

    /// The degrees back - nil for anything else.
    public init?(propValue: PropValue) {
        guard let degrees = propValue.number else { return nil }
        self = .degrees(degrees)
    }
}

extension Angle: ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    /// A literal is degrees, so `.rotationEffect(45)` turns a quarter of a
    /// right angle - radians are said `.radians(_:)`.
    public init(integerLiteral value: Int) {
        self = .degrees(Double(value))
    }

    /// The same, for a fractional one.
    public init(floatLiteral value: Double) {
        self = .degrees(value)
    }
}

extension Angle: StateValue {
    /// One lane: the degrees.
    public var carried: StateCarried { .lanes([degrees]) }

    /// And back, as degrees.
    public init?(carried: StateCarried) {
        guard case .lanes(let lanes) = carried, lanes.count == 1 else { return nil }
        self = .degrees(lanes[0])
    }

    /// One.
    public static var lanes: Int { 1 }
}

extension Angle: Walked {}
