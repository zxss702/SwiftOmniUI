// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Where a view sits in a Grid or a ZStack, written on the view. The property
// half lives on `ViewProperties`, which a `Style` targeting a view also
// carries; the `@_disfavoredOverload` twins on `View` answer a composed view.
// Design: docs/design/views/modifiers.md#placement-is-written-on-the-child

extension ViewProperties {
    /// Which row of the enclosing Grid the view sits in, counting from 0.
    ///
    ///     Text("Name").gridRow(0).gridColumn(0)
    ///     TextField($name).gridRow(0).gridColumn(1)
    @_spi(Host) public func gridRow(_ value: Int) -> Modified { setValue(ViewContract.gridRow, value) }

    /// Which column of the enclosing Grid the view sits in, counting from 0.
    @_spi(Host) public func gridColumn(_ value: Int) -> Modified { setValue(ViewContract.gridColumn, value) }

    /// How many rows the view covers, starting at its own.
    @_spi(Host) public func gridRowSpan(_ value: Int) -> Modified { setValue(ViewContract.gridRowSpan, value) }

    /// How many columns the view covers, starting at its own.
    @_spi(Host) public func gridColumnSpan(_ value: Int) -> Modified { setValue(ViewContract.gridColumnSpan, value) }

    /// The part of the enclosing ZStack's room the view stands in, in device
    /// units or in fractions of the room; the whole room without it.
    ///
    ///     Text("Right half").area(.proportional(0.5, 0, 0.5, 1))
    @_spi(Host) public func area(_ value: Area) -> Modified { setValue(ViewContract.area, value) }
}

extension ViewProperties {
    /// `gridColumn` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func gridColumn(_ state: Binding<Int>) -> Modified {
        plain(ViewContract.gridColumn, by: state)
    }

    /// `gridColumnSpan` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func gridColumnSpan(_ state: Binding<Int>) -> Modified {
        plain(ViewContract.gridColumnSpan, by: state)
    }

    /// `gridRow` from a state, `$x`: the host sets each new value as it stands,
    /// and no view is rebuilt for it.
    @_spi(Host) public func gridRow(_ state: Binding<Int>) -> Modified {
        plain(ViewContract.gridRow, by: state)
    }

    /// `gridRowSpan` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func gridRowSpan(_ state: Binding<Int>) -> Modified {
        plain(ViewContract.gridRowSpan, by: state)
    }
}

extension View {
    /// Which row of the enclosing Grid the view sits in, counting from 0.
    ///
    ///     Text("Name").gridRow(0).gridColumn(0)
    ///     TextField($name).gridRow(0).gridColumn(1)
    @_disfavoredOverload
    @_spi(Host) public func gridRow(_ value: Int) -> ModifiedContent { setting(ViewContract.gridRow, value) }

    /// Which column of the enclosing Grid the view sits in, counting from 0.
    @_disfavoredOverload
    @_spi(Host) public func gridColumn(_ value: Int) -> ModifiedContent { setting(ViewContract.gridColumn, value) }

    /// How many rows the view covers, starting at its own.
    @_disfavoredOverload
    @_spi(Host) public func gridRowSpan(_ value: Int) -> ModifiedContent { setting(ViewContract.gridRowSpan, value) }

    /// How many columns the view covers, starting at its own.
    @_disfavoredOverload
    @_spi(Host) public func gridColumnSpan(_ value: Int) -> ModifiedContent { setting(ViewContract.gridColumnSpan, value) }

    /// The part of the enclosing ZStack's room the view stands in, in device
    /// units or in fractions of the room; the whole room without it.
    ///
    ///     Text("Right half").area(.proportional(0.5, 0, 0.5, 1))
    @_disfavoredOverload
    @_spi(Host) public func area(_ value: Area) -> ModifiedContent { setting(ViewContract.area, value) }
}

extension View {
    /// `gridColumn` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_disfavoredOverload
    @_spi(Host) public func gridColumn(_ state: Binding<Int>) -> ModifiedContent {
        revised { $0.drivePlain(ViewContract.gridColumn, by: state) }
    }

    /// `gridColumnSpan` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_disfavoredOverload
    @_spi(Host) public func gridColumnSpan(_ state: Binding<Int>) -> ModifiedContent {
        revised { $0.drivePlain(ViewContract.gridColumnSpan, by: state) }
    }

    /// `gridRow` from a state, `$x`: the host sets each new value as it stands,
    /// and no view is rebuilt for it.
    @_disfavoredOverload
    @_spi(Host) public func gridRow(_ state: Binding<Int>) -> ModifiedContent {
        revised { $0.drivePlain(ViewContract.gridRow, by: state) }
    }

    /// `gridRowSpan` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_disfavoredOverload
    @_spi(Host) public func gridRowSpan(_ state: Binding<Int>) -> ModifiedContent {
        revised { $0.drivePlain(ViewContract.gridRowSpan, by: state) }
    }

    /// Where the grid cell holding this view aligns it across the column -
    /// the cell's say, which is what a column of like-aligned cells comes to:
    ///
    ///     cellContent()
    ///         .gridColumnAlignment(.trailing)
    ///
    /// The SwiftUI spelling of SwiftOmniUI's `horizontalAlignment` on a grid
    /// child.
    public func gridColumnAlignment(_ alignment: HorizontalAlignment) -> ModifiedContent {
        setting(ViewContract.horizontalAlignment, alignment.axis)
    }

    /// How many columns this grid cell covers, counting from its own -
    /// SwiftUI's `.gridCellColumns(2)`.
    public func gridCellColumns(_ count: Int) -> ModifiedContent {
        setting(ViewContract.gridColumnSpan, count)
    }
}
