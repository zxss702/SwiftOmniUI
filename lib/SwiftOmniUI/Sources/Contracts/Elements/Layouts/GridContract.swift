// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Arranges its children in rows and columns.
public enum GridContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "Grid"

    /// SwiftOmniUI composes it from smaller primitives before a host receives the
    /// tree.
    public static let layer: ElementLayer = .stateUI

    /// A grid is a layout.
    public static let tiers: [any Contract.Type] = [LayoutContract.self]

    /// The gap between one column and the next, in device units.
    public static let columnSpacing = ElementProperty<Self, Double>(
        "columnSpacing", layer: .stateUI, moves: .spacing)

    /// How wide each column is, one length per column.
    public static let columns = ElementProperty<Self, [GridLength]>("columns", layer: .stateUI)

    /// The gap between one row and the next, in device units.
    public static let rowSpacing = ElementProperty<Self, Double>(
        "rowSpacing", layer: .stateUI, moves: .spacing)

    /// How tall each row is, one length per row.
    public static let rows = ElementProperty<Self, [GridLength]>("rows", layer: .stateUI)

    /// The columns a `LazyVGrid` describes: the children fill them row
    /// first, an `.adaptive` one standing for as many as fit.
    public static let flowColumns = ElementProperty<Self, [GridItem]>("flowColumns", layer: .stateUI)

    /// SwiftUI GridRow grids fit their implicit tracks to cell content.
    public static let contentSizedTracks = ElementProperty<Self, Bool>("contentSizedTracks", layer: .stateUI)

    /// The element's own members.
    public static let members: [any ContractMember] = [columnSpacing, columns, flowColumns, rowSpacing, rows, contentSizedTracks]
}
