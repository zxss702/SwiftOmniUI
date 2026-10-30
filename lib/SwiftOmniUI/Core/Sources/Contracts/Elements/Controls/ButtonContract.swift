// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A button with a caption, and a handler for the press.
public enum ButtonContract: ElementContract {
    /// The node type the contract declares.
    public static let nodeType: NodeType = "Button"

    /// Every base host presents it with its native control.
    public static let layer: ElementLayer = .native

    /// A button is a view with a caption in a font, padded, bordered, with a
    /// picture fitted.
    public static let tiers: [any Contract.Type] = [
        ViewContract.self, TextElementContract.self, FontElementContract.self, PaddingElementContract.self,
        BorderElementContract.self, ImageElementContract.self,
        ControlSizeElementContract.self,
    ]

    /// The look `.buttonStyle` asks for - the platform's own drawing of the
    /// kind.
    public static let buttonStyle = ElementProperty<Self, ButtonStyleKind>("buttonStyle", layer: .native)

    /// The button was pressed and released on it.
    public static let clicked = ElementEvent<Self, Void>("clicked", layer: .native)

    /// The picture beside the caption.
    public static let icon = ElementProperty<Self, ImageSource>("icon", layer: .adaptive)

    /// Which side of the caption the icon stands on.
    public static let iconPosition = ElementProperty<Self, IconPosition>("iconPosition", layer: .adaptive)

    /// The gap between the icon and the caption, in device units.
    public static let iconSpacing = ElementProperty<Self, Double>("iconSpacing", layer: .adaptive)

    /// What happens to a caption too long for the button.
    public static let lineBreak = ElementProperty<Self, LineBreak>("lineBreak", layer: .native)

    /// A button that keeps its pressed look while on - what a toggle's
    /// `.button` style draws. The member's being there at all makes the
    /// button a staying-pressed one; every press flips it, reported through
    /// `toggled`.
    public static let isOn = ElementProperty<Self, Bool>("isOn", layer: .native)

    /// The staying-pressed button flipped - `true` for now pressed, `false`
    /// for released.
    public static let toggled = ElementEvent<Self, Bool>("toggled", layer: .native)

    /// A press began on the button: a finger, a pen or a mouse button went down.
    public static let pressed = ElementEvent<Self, Void>("pressed", layer: .native)

    /// The press ended, wherever the pointer ended up.
    public static let released = ElementEvent<Self, Void>("released", layer: .native)

    /// What the button does to what it touches - ordinary, cancelling or
    /// destructive: how the platform marks it, where it marks one.
    public static let role = ElementProperty<Self, ButtonRole>("role", layer: .adaptive)

    /// A keyboard shortcut that clicks the button from anywhere in its window.
    public static let shortcut = ElementProperty<Self, KeyboardShortcut>("shortcut", layer: .native)

    /// The element's own members.
    public static let members: [any ContractMember] = [
        buttonStyle, clicked, icon, iconPosition, iconSpacing, isOn, lineBreak, pressed, released,
        role, shortcut, toggled,
    ]
}
