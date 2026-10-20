// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `Grid`'s own properties, shared by the control and its `Style<Grid>`.
public protocol GridProperties: PropertyContainer {}

extension GridProperties {
    /// How tall each row is - one length per row, so the count says how many
    /// rows there are.
    ///
    ///     .rows(.auto, .fill, .proportional(2), .fixed(100))
    ///
    /// `.auto` fits what is in the row, `.fill` and `.proportional` take a
    /// share of what is left over, and `.fixed` is that many device units. A
    /// grid told nothing has one row and one column.
    @_spi(Host) public func rows(_ lengths: GridLength...) -> Modified {
        setValue(GridContract.rows, lengths)
    }

    /// How wide each column is - one length per column, so the count says how
    /// many columns there are.
    ///
    ///     .columns(.fill, .proportional(2))
    ///
    /// The same kinds of length as `rows`.
    @_spi(Host) public func columns(_ lengths: GridLength...) -> Modified {
        setValue(GridContract.columns, lengths)
    }

    /// The gap between one row and the next, in device units - between the rows
    /// only; the space around the whole grid is `.padding`.
    @_spi(Host) public func rowSpacing(_ value: Double) -> Modified {
        setValue(GridContract.rowSpacing, value)
    }

    /// The gap between one column and the next, in device units.
    @_spi(Host) public func columnSpacing(_ value: Double) -> Modified {
        setValue(GridContract.columnSpacing, value)
    }
}

/// Arranges its children in rows and columns.
///
///     Grid {
///         Text("Column 0, Row 0")
///
///         Text("Column 1, Row 0")
///             .gridColumn(1)
///
///         Text("Spanning both")
///             .gridRow(1)
///             .gridColumnSpan(2)
///     }
///     .rows(.auto, .fill)
///     .columns(.fill, .proportional(2))
///     .rowSpacing(12)
///     .columnSpacing(12)
///
/// Where a child sits is written on the child, with `.gridRow` and
/// `.gridColumn`.
///
/// A child that says nothing sits in row 0, column 0 - which is how two
/// children end up on top of one another if that was not intended.
public struct Grid: LayoutView, GridProperties {
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<Grid>` is written against.
    public init() {
        node = Node(contract: GridContract.self)
    }

    /// A grid holding what the closure describes. The closure runs when the
    /// differ reaches the grid.
    public init(@ViewBuilder content: @escaping () -> any View) {
        node = Node(contract: GridContract.self)
        node.producer = { content().node.asChildren }
    }

    /// A grid of `GridRow`s, each a row of cells one to a column - SwiftUI's
    /// `Grid(alignment:horizontalSpacing:verticalSpacing:content:)`:
    ///
    ///     Grid(horizontalSpacing: 0, verticalSpacing: 0) {
    ///         GridRow { Text("Name"); Text("Value") }
    ///         GridRow { Text("Font"); Text("Serif") }
    ///     }
    ///
    /// A child that is no `GridRow` stands as a row of its own spanning the
    /// columns the rows make. The columns and rows fit what they hold.
    ///
    /// - Parameters:
    ///   - horizontalSpacing: the gap between two columns.
    ///   - verticalSpacing: the gap between two rows.
    ///   - content: the rows.
    public init(
        horizontalSpacing: Double?,
        verticalSpacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        self.init(
            alignment: .center,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing,
            content: content)
    }

    /// A grid of `GridRow`s, aligned as `alignment` says where a cell or its
    /// row does not.
    ///
    /// - Parameters:
    ///   - alignment: where a cell's content sits in its cell, where the cell
    ///     and its row do not say.
    ///   - content: the rows.
    public init(alignment: Alignment, @ViewBuilder content: @escaping () -> any View) {
        self.init(alignment: alignment, horizontalSpacing: nil, verticalSpacing: nil, content: content)
    }

    /// A grid of `GridRow`s, aligned and spaced as stated.
    ///
    /// - Parameters:
    ///   - alignment: where a cell's content sits in its cell, where the cell
    ///     and its row do not say.
    ///   - horizontalSpacing: the gap between two columns.
    ///   - verticalSpacing: the gap between two rows.
    ///   - content: the rows.
    public init(
        alignment: Alignment,
        horizontalSpacing: Double?,
        verticalSpacing: Double?,
        @ViewBuilder content: @escaping () -> any View
    ) {
        node = Node(contract: GridContract.self)
        if let horizontalSpacing { node.write(GridContract.columnSpacing, horizontalSpacing) }
        if let verticalSpacing { node.write(GridContract.rowSpacing, verticalSpacing) }
        node.write(GridContract.contentSizedTracks, true)
        node.producer = { Self.cells(of: content().node.asChildren, alignment: alignment) }
    }

    /// The cells the rows describe, each stamped with its row and column - a
    /// `GridRow`'s children one to a column, a bare child a row of its own
    /// spanning every column the rows make.
    private static func cells(of children: [Node], alignment: Alignment) -> [Node] {
        let rows = children.map { child -> (bare: Bool, alignment: AxisAlignment, cells: [Node]) in
            guard child.type == GridRowContract.nodeType else { return (true, .fill, [child]) }
            let axis = AxisAlignment(rawValue: child.props[.verticalAlignment]?.enumeration ?? -1)
                ?? alignment.vertical.axis
            return (false, axis, child.producer?() ?? [])
        }
        let columns = max(rows.map(\.cells.count).max() ?? 1, 1)
        var cells: [Node] = []

        for (row, laid) in rows.enumerated() {
            for (column, cell) in laid.cells.enumerated() {
                var cell = cell
                cell.write(ViewContract.gridRow, row)
                cell.write(ViewContract.gridColumn, column)
                if laid.bare {
                    cell.write(ViewContract.gridColumnSpan, columns)
                } else {
                    if alignment.horizontal.axis != .fill {
                        cell.write(ViewContract.horizontalAlignment, alignment.horizontal.axis)
                    }
                    if laid.alignment != .fill {
                        cell.write(ViewContract.verticalAlignment, laid.alignment)
                    }
                }
                cells.append(cell)
            }
        }

        return cells
    }
}

extension Grid {
    /// `columnSpacing` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func columnSpacing(_ state: Binding<Double>) -> Modified {
        plain(.columnSpacing, by: state)
    }

    /// `rowSpacing` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func rowSpacing(_ state: Binding<Double>) -> Modified {
        plain(.rowSpacing, by: state)
    }
}
