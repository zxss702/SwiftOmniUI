// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What shows behind a scrollable view's content - a list's or an editor's
/// own canvas, where the platform draws one.
public enum ScrollContentElementContract: Contract {
    /// The tier's name.
    public static let name = "ScrollContentElement"

    /// The background is carried as a value in the tree.
    public static let tiers: [any Contract.Type] = [PropertyContainerContract.self]

    /// Whether the platform's own canvas shows behind the content.
    public static let scrollContentBackground = ElementProperty<Self, Visibility>(
        "scrollContentBackground", layer: .native)

    /// The tier's own members.
    public static let members: [any ContractMember] = [scrollContentBackground]
}
