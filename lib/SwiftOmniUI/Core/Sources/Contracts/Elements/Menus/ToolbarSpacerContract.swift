// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Room between the items of a page's toolbar - `ToolbarSpacer` writes it.
public enum ToolbarSpacerContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "ToolbarSpacer"

    /// It carries structure, not a platform control of its own.
    public static let layer: ElementLayer = .structure

    /// Whether it stands on the bar itself or, where a spacer can, in the overflow.
    public static let placement = ElementProperty<Self, ToolbarItemPlacement>(
        "placement", layer: .adaptive, travels: false, cleared: false)

    /// How much room it takes - all of it, or the platform's gap.
    public static let variant = ElementProperty<Self, ToolbarSpacerVariant>(
        "variant", layer: .adaptive, travels: false, cleared: false)

    /// The element's own members.
    public static let members: [any ContractMember] = [placement, variant]
}
