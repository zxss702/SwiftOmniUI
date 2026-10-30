// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// Where a view sits on ONE axis of the space its layout gives it - what
/// `horizontalAlignment` and `verticalAlignment` carry across the boundary.
/// The view-facing vocabulary is `HorizontalAlignment`, `VerticalAlignment`
/// and `Alignment`; this is the contract's.
public enum AxisAlignment: Int32, Sendable {
    /// At the near edge - the left, or the top - taking only the room it needs.
    case start = 0

    /// In the middle, taking only the room it needs.
    case center = 1

    /// At the far edge, taking only the room it needs.
    case end = 2

    /// Taking all of it. The default.
    case fill = 3

    /// On a text row's first baseline - a `VerticalAlignment` only.
    case firstTextBaseline = 4

    /// On a text row's last baseline - a `VerticalAlignment` only.
    case lastTextBaseline = 5
}

extension AxisAlignment: HostRepresentable {}
extension AxisAlignment: StateChoice {}

/// A horizontal alignment: where children sit across a `VStack`, or a view in
/// its frame.
public struct HorizontalAlignment: Equatable, Sendable {
    /// The axis value this alignment carries.
    public var axis: AxisAlignment

    /// An alignment of the given axis value.
    public init(_ axis: AxisAlignment) {
        self.axis = axis
    }

    /// At the left - the leading edge.
    public static let leading = HorizontalAlignment(.start)

    /// In the middle.
    public static let center = HorizontalAlignment(.center)

    /// At the right - the trailing edge.
    public static let trailing = HorizontalAlignment(.end)
}

/// A vertical alignment: where children sit down an `HStack`, or a view in its
/// frame.
public struct VerticalAlignment: Equatable, Sendable {
    /// The axis value this alignment carries.
    public var axis: AxisAlignment

    /// An alignment of the given axis value.
    public init(_ axis: AxisAlignment) {
        self.axis = axis
    }

    /// At the top.
    public static let top = VerticalAlignment(.start)

    /// In the middle.
    public static let center = VerticalAlignment(.center)

    /// At the bottom.
    public static let bottom = VerticalAlignment(.end)

    /// On the first text baseline of a row.
    public static let firstTextBaseline = VerticalAlignment(.firstTextBaseline)

    /// On the last text baseline of a row.
    public static let lastTextBaseline = VerticalAlignment(.lastTextBaseline)
}

/// An alignment on both axes: where a view sits in the room its frame, `ZStack`
/// or overlay gives it.
///
///     Text("New").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
public struct Alignment: Equatable, Sendable {
    /// Where it sits across.
    public var horizontal: HorizontalAlignment

    /// Where it sits down.
    public var vertical: VerticalAlignment

    /// An alignment of the two axes.
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// Middle on both axes.
    public static let center = Alignment(horizontal: .center, vertical: .center)

    /// At the left edge, in the middle.
    public static let leading = Alignment(horizontal: .leading, vertical: .center)

    /// At the right edge, in the middle.
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)

    /// At the top, in the middle.
    public static let top = Alignment(horizontal: .center, vertical: .top)

    /// At the bottom, in the middle.
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)

    /// The top left corner.
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)

    /// The top right corner.
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)

    /// The bottom left corner.
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)

    /// The bottom right corner.
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)

    /// On the first text baseline, at the leading edge.
    public static let leadingFirstTextBaseline = Alignment(horizontal: .leading, vertical: .firstTextBaseline)

    /// On the first text baseline, in the middle.
    public static let centerFirstTextBaseline = Alignment(horizontal: .center, vertical: .firstTextBaseline)

    /// On the first text baseline, at the trailing edge.
    public static let trailingFirstTextBaseline = Alignment(horizontal: .trailing, vertical: .firstTextBaseline)

    /// On the last text baseline, at the leading edge.
    public static let leadingLastTextBaseline = Alignment(horizontal: .leading, vertical: .lastTextBaseline)

    /// On the last text baseline, in the middle.
    public static let centerLastTextBaseline = Alignment(horizontal: .center, vertical: .lastTextBaseline)

    /// On the last text baseline, at the trailing edge.
    public static let trailingLastTextBaseline = Alignment(horizontal: .trailing, vertical: .lastTextBaseline)
}

/// A point in a view's own terms, as a fraction of it - what the `anchor:` of a
/// scale, a rotation or a transition takes.
///
/// `.center` is the middle, `.topLeading` the top left corner; `UnitPoint(x:y:)`
/// names anywhere else, 0 to 1 across the view and down it.
public struct UnitPoint: Equatable, Sendable {
    /// The fraction across: 0 the left edge, 1 the right.
    public var x: Double

    /// The fraction down: 0 the top edge, 1 the bottom.
    public var y: Double

    /// A point of the two fractions.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The top left corner.
    public static let zero = UnitPoint(x: 0, y: 0)

    /// The middle.
    public static let center = UnitPoint(x: 0.5, y: 0.5)

    /// The middle of the top edge.
    public static let top = UnitPoint(x: 0.5, y: 0)

    /// The middle of the bottom edge.
    public static let bottom = UnitPoint(x: 0.5, y: 1)

    /// The middle of the left edge.
    public static let leading = UnitPoint(x: 0, y: 0.5)

    /// The middle of the right edge.
    public static let trailing = UnitPoint(x: 1, y: 0.5)

    /// The top left corner.
    public static let topLeading = UnitPoint(x: 0, y: 0)

    /// The top right corner.
    public static let topTrailing = UnitPoint(x: 1, y: 0)

    /// The bottom left corner.
    public static let bottomLeading = UnitPoint(x: 0, y: 1)

    /// The bottom right corner.
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

extension UnitPoint: HostRepresentable {
    /// The two fractions.
    public var propValue: PropValue { .numbers([x, y]) }

    /// The point those numbers stand for, or nil where they are not two.
    /// - Parameter propValue: what the host sent.
    public init?(propValue: PropValue) {
        guard let numbers = propValue.numbers, numbers.count == 2 else { return nil }
        self.init(x: numbers[0], y: numbers[1])
    }
}

extension UnitPoint: StateValue {
    /// The two fractions, as lanes.
    public var carried: StateCarried { .lanes([x, y]) }

    /// The point those lanes stand for.
    /// - Parameter carried: what the state holds.
    public init?(carried: StateCarried) {
        guard case .lanes(let lanes) = carried, lanes.count == 2 else { return nil }
        self.init(x: lanes[0], y: lanes[1])
    }

    /// Two.
    public static var lanes: Int { 2 }
}
