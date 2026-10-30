// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Space on the four sides of something.
///
///     VStack { … }.contentPadding(24)
///     Text("Total").padding(0, 8, 0, 16)
///
/// `.contentPadding` keeps it INSIDE the control, between its edge and its
/// content; `.padding` keeps it OUTSIDE, between the control and its
/// neighbours. A number written where one of these is wanted becomes the same
/// value on all four sides.
public struct EdgeInsets: Equatable, Sendable, HostRepresentable, ExpressibleByIntegerLiteral {
    /// The space on the left, in device units.
    public var left: Double

    /// The space above.
    public var top: Double

    /// The space on the right.
    public var right: Double

    /// The space below.
    public var bottom: Double

    /// The same value on all four sides.
    public init(_ uniformSize: Double) {
        self.init(uniformSize, uniformSize, uniformSize, uniformSize)
    }

    /// The same value on all four sides, as a number literal.
    public init(integerLiteral value: Int) {
        self.init(Double(value))
    }

    /// Each edge by name, in the order SwiftUI writes them.
    ///
    ///     EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.init(leading, top, trailing, bottom)
    }

    /// Left and right first, then top and bottom.
    ///
    ///     EdgeInsets(16, 8)   // 16 either side, 8 above and below
    public init(_ horizontalSize: Double, _ verticalSize: Double) {
        self.init(horizontalSize, verticalSize, horizontalSize, verticalSize)
    }

    /// Each side in turn: left, top, right, bottom - clockwise from the LEFT,
    /// not from the top.
    public init(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// As a host is handed it: an array, in the four-value initializer's order.
    public var propValue: PropValue {
        .numbers([left, top, right, bottom])
    }

    /// EdgeInsets back from their four numbers - nil for anything else.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard let numbers = propValue.numbers, numbers.count == 4 else { return nil }

        self.init(numbers[0], numbers[1], numbers[2], numbers[3])
    }

    /// The two added side by side - a scroll view's own padding and the room
    /// a bar over it keeps clear, among the things they add up to.
    public static func + (one: EdgeInsets, other: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            one.left + other.left, one.top + other.top,
            one.right + other.right, one.bottom + other.bottom)
    }
}


