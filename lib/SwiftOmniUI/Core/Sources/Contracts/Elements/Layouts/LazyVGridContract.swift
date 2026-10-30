// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A grid a scroller builds a row at a time as it scrolls into view: the
/// cells fill its columns row first, and the host asks for the rows in view.
///
///     ScrollView {
///         LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))]) { … }
///     }
public enum LazyVGridContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "LazyVGrid"

    /// Every host shows it with a container of its own.
    public static let layer: ElementLayer = .native

    /// A lazy grid is a layout, and its content backs a scroller.
    public static let tiers: [any Contract.Type] = [LayoutContract.self, ScrollContentElementContract.self]

    /// Every cell's identity in the order it shows - row first, as written.
    public static let items = ElementProperty<Self, [String]>("items", layer: .native, travels: false)

    /// The columns the cells fill, an `.adaptive` one standing for as many as
    /// the room the host gives it fits.
    public static let flowColumns = ElementProperty<Self, [GridItem]>("flowColumns", layer: .stateUI)

    /// The gap between one column and the next - a column item's own
    /// `spacing`, or the grid's where none says.
    public static let columnSpacing = ElementProperty<Self, Double>(
        "columnSpacing", layer: .stateUI, moves: .spacing)

    /// The gap between one row and the next.
    public static let rowSpacing = ElementProperty<Self, Double>(
        "rowSpacing", layer: .stateUI, moves: .spacing)

    /// The identities standing in or near view, whose subtrees the host needs
    /// built.
    public static let realizedChanged = ElementEvent<Self, [String]>(
        "realizedChanged", layer: .structure)

    /// The element's own members.
    public static let members: [any ContractMember] = [
        items, columnSpacing, flowColumns, rowSpacing, realizedChanged,
    ]
}

