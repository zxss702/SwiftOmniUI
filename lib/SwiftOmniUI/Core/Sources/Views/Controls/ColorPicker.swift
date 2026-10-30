// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `ColorPicker`'s own properties, shared by the control and its
/// `Style<ColorPicker>`.
public protocol ColorPickerProperties: PropertyContainer {}

extension ColorPickerProperties {
    /// What the rectangle is filled with. Use this rather than `.background`,
    /// a second surface behind the box that its corner radius does not round.
    public func color(_ value: Color) -> Modified {
        setValue(ColorPickerContract.color, value)
    }

    /// How rounded the corners are, in device units - the same radius on all
    /// four.
    ///
    /// A radius of half the side turns a square box into a circle.
    public func cornerRadius(_ value: Double) -> Modified {
        setValue(ColorPickerContract.cornerRadius, .uniform(value))
    }

    /// One corner at a time, in SwiftOmniUI's declared order.
    ///
    ///     ColorPicker().cornerRadius(topLeft: 16, topRight: 16, bottomLeft: 0, bottomRight: 0)
    ///
    /// - Parameters:
    ///   - topLeft: the top left corner.
    ///   - topRight: the top right corner.
    ///   - bottomLeft: the bottom left corner.
    ///   - bottomRight: the bottom right corner.
    public func cornerRadius(
        topLeft: Double,
        topRight: Double,
        bottomLeft: Double,
        bottomRight: Double
    ) -> Modified {
        setValue(
            ColorPickerContract.cornerRadius,
            .corners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight))
    }
}

/// A host-native rectangle of colour.
///
///     ColorPicker()
///         .color(.cornflowerBlue)
///         .cornerRadius(8)
///         .frame(height: 40)
///
/// The simplest thing a host draws: a divider, a bar of a chart, a placeholder,
/// or a deliberate piece of empty space. It has no content and no children -
/// for a coloured area around something, give the layout holding it a
/// background.
public struct ColorPicker: VisualElement, ColorPickerProperties{
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<ColorPicker>` is written against.
    public init() {
        node = Node(contract: ColorPickerContract.self)
    }

    /// A rectangle drawn in `color`. Sized by `.width` and
    /// `.height`, or by the room the layout gives it.
    public init(_ color: Color) {
        node = Node(contract: ColorPickerContract.self)
        node.write(ColorPickerContract.color, color)
    }

}

extension ColorPicker {
    /// `color` from a state, `$x`: the host animates the property to each new
    /// value, and no view is rebuilt for it.
    /// Not `.background`, which is a second square behind the one a box draws.
    public func color(_ state: Binding<Color>) -> Modified {
        journey(.color, by: state)
    }

    /// `cornerRadius` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    public func cornerRadius(_ state: Binding<Double>) -> Modified {
        plain(ColorPickerContract.cornerRadius.token, by: state)
    }
}
