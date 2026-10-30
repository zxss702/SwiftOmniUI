// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Draws its first child as its second child's alpha allows - a `.mask`
/// realized: the mask is laid out in the same room and never drawn; where it
/// paints opaque the content shows, where it paints clear nothing does.
public enum MaskedContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "Masked"

    /// Every base host presents it with its native compositing.
    public static let layer: ElementLayer = .native

    /// It holds two children in one room: the content, then the mask.
    public static let tiers: [any Contract.Type] = [LayoutContract.self]

    /// The element's own members.
    public static let members: [any ContractMember] = []
}
