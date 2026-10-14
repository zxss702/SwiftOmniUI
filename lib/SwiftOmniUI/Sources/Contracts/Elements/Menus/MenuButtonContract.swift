// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A menu that lives in the view: a button whose label opens its entries.
public enum MenuButtonContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "MenuButton"

    /// Every base host presents it with its native menu button.
    public static let layer: ElementLayer = .native

    /// A menu button is a view.
    public static let tiers: [any Contract.Type] = [ViewContract.self]

    /// How the trigger draws - a token like `"borderlessButton"`;
    /// `.menuStyle` writes it.
    public static let menuStyle = ElementProperty<Self, String>("menuStyle", layer: .native)

    public static let buttonStyle = ElementProperty<Self, ButtonStyleKind>("buttonStyle", layer: .native)
    @_spi(Host) public static let contentRequested = ElementEvent<Self, Void>("menuContentRequested", layer: .native)

    /// Whether the trigger shows the mark that says it opens a menu;
    /// `.menuIndicator` writes it.
    public static let menuIndicator = ElementProperty<Self, MenuIndicatorVisibility>(
        "menuIndicator", layer: .native)

    /// The element's own members.
    public static let members: [any ContractMember] = [menuIndicator, menuStyle, buttonStyle, contentRequested]
}
