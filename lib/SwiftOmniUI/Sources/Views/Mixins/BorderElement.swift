// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What an element draws of its own box - a layout's, a scroller's, a
/// button's: the shape its background fills, and an outline on it.
///
///     Button("Save")
///         .stroke(.cornflowerBlue)
///         .strokeWidth(1)
///         .shape(.roundedRectangle(8))
@preconcurrency @MainActor public protocol BorderElement: PropertyContainer {}

extension BorderElement {
    /// The shape the background and the outline follow, and - with `clipsContent` - what the element holds.
    public func shape(_ value: ContainerShape) -> Modified {
        setValue(BorderElementContract.shape, value)
    }

    /// What the outline is painted with; nothing is outlined without one.
    public func stroke(_ value: Brush) -> Modified {
        setValue(BorderElementContract.stroke, value)
    }

    /// The outline in one colour.
    public func stroke(_ value: Color) -> Modified {
        stroke(.solidColor(value))
    }

    /// The same, `width` wide - colour and thickness said together.
    public func stroke(_ value: Brush, width: Double) -> Modified {
        modified {
            $0.props[BorderElementContract.stroke.token] = value.propValue
            $0.write(BorderElementContract.strokeWidth, width)
        }
    }

    /// The same, in one colour.
    public func stroke(_ value: Color, width: Double) -> Modified {
        stroke(.solidColor(value), width: width)
    }

    /// How wide the outline is, in device units; one where none is said.
    @_spi(Host) public func strokeWidth(_ value: Double) -> Modified {
        setValue(BorderElementContract.strokeWidth, value)
    }
}

extension BorderElement where Self: VisualElement {
    /// `strokeWidth` from a state, `$x`: the host animates the outline to each new width, and no view is
    /// rebuilt for it.
    @_spi(Host) public func strokeWidth(_ state: Binding<Double>) -> Modified {
        journey(BorderElementContract.strokeWidth, by: state)
    }
}
