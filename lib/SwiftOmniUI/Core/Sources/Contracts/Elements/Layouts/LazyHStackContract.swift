// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A row a scroller builds as it scrolls into view - `LazyVStack` across.
public enum LazyHStackContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "LazyHStack"

    /// Every host shows it with a container of its own.
    public static let layer: ElementLayer = .native

    /// A lazy row is a stack.
    public static let tiers: [any Contract.Type] = [StackBaseContract.self, ScrollContentElementContract.self]

    /// Every child's identity in the order it shows.
    public static let items = ElementProperty<Self, [String]>("items", layer: .native, travels: false)

    /// The identities standing in or near view, whose subtrees the host needs
    /// built.
    public static let realizedChanged = ElementEvent<Self, [String]>(
        "realizedChanged", layer: .structure)

    /// The element's own members.
    public static let members: [any ContractMember] = [items, realizedChanged]
}

