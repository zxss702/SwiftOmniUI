// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Places its children by an author's own `Layout` - a container whose
/// measure and place passes run the layout object's methods rather than a
/// built-in arithmetic.
public enum CustomLayoutContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "CustomLayout"

    /// The host runs the container; the layout object that steers it rides
    /// the node and never crosses the wire.
    public static let layer: ElementLayer = .native

    /// A custom layout is a layout; spacing and alignment are the layout
    /// object's own, not a stack's, so it takes no StackBase.
    public static let tiers: [any Contract.Type] = [LayoutContract.self]

    /// The element's own members.
    public static let members: [any ContractMember] = []
}
