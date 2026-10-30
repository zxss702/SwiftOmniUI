// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A menu: a caption and the entries it opens - on the menu bar, or one level
/// down inside another menu.
public enum MenuContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "Menu"

    /// It carries structure, not a platform control of its own.
    public static let layer: ElementLayer = .structure

    /// Whether the menu opens at all.
    public static let isEnabled = ElementProperty<Self, Bool>("isEnabled", layer: .native)

    /// The caption.
    public static let text = ElementProperty<Self, String>("text", layer: .native)

    /// The caption as a lookup key, as `TextElementContract.textKey` is for
    /// the elements that wear it.
    public static let textKey = ElementProperty<Self, LocalizedStringKey>(
        "textKey", layer: .native, travels: false)

    /// The menu's place among the platform's own menus, where the element
    /// stands for a command group rather than a menu of its own: the region
    /// its entries splice into, nil where the menu is an ordinary one.
    public static let placement = ElementProperty<Self, CommandGroupPlacement>(
        "placement", layer: .adaptive, travels: false, cleared: false)

    /// The element's own members.
    public static let members: [any ContractMember] = [isEnabled, placement, text, textKey]
}
