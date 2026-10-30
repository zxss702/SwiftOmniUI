// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// One row of cells inside a `Grid` - structure the grid reads while it
/// lays its cells out, never an element a host mounts.
public enum GridRowContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "GridRow"

    /// It carries structure rather than configuring a visual platform object.
    public static let layer: ElementLayer = .structure

    /// A grid row is a layout child.
    public static let tiers: [any Contract.Type] = [LayoutContract.self]

    /// The element's own members.
    public static let members: [any ContractMember] = []
}
