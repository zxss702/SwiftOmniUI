// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A column a scroller builds as it scrolls into view: SwiftOmniUI says which
/// children there are, in order, and builds the ones the host asks for; the
/// host keeps them stacked, measures the ones it holds, and stands the rest
/// for by their measure so the scroll room is known before they exist.
///
///     ScrollView {
///         LazyVStack(spacing: 12) { … }
///     }
///
/// The host asks by `realizedChanged`: the identities in view, and a reach
/// around them; those are the only subtrees the tree keeps mounted. An
/// identity leaves view and its subtree is let go - a state it declared goes
/// with it, the way a `List` cell's does.
public enum LazyVStackContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "LazyVStack"

    /// Every host shows it with a container of its own.
    public static let layer: ElementLayer = .native

    /// A lazy column is a stack.
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

