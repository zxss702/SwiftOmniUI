// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// One row of cells inside a `Grid` - SwiftUI's `GridRow`:
///
///     Grid(horizontalSpacing: 0, verticalSpacing: 0) {
///         GridRow {
///             Text("Name")
///             Text("Value")
///         }
///         GridRow {
///             Text("Font")
///             Text("Serif")
///         }
///     }
///
/// The `Grid` it stands in lays the row's children out one to a column;
/// outside a `Grid` a row stands as what it holds.
public struct GridRow<Content: View>: View {
    /// The node this row describes: a marker the `Grid` it stands in splices
    /// its cells out of, its own `verticalAlignment` the cells' where they
    /// do not say.
    public var node: Node

    /// A row of what the closure describes.
    ///
    /// - Parameters:
    ///   - content: the cells, one to a column.
    public init(@ViewBuilder content: @escaping () -> Content) {
        node = Node(contract: GridRowContract.self)
        node.producer = { content().node.asChildren }
    }

    /// A row of what the closure describes, its cells `alignment`d down it
    /// where a cell does not say.
    ///
    /// - Parameters:
    ///   - alignment: where a cell's content sits down its row.
    ///   - content: the cells, one to a column.
    public init(alignment: VerticalAlignment, @ViewBuilder content: @escaping () -> Content) {
        node = Node(contract: GridRowContract.self)
        node.write(ViewContract.verticalAlignment, alignment.axis)
        node.producer = { content().node.asChildren }
    }
}
