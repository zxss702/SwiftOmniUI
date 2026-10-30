// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Menu styles: how a Menu button draws its trigger - a bordered button, a
// bare label that opens on a click. The kind crosses as a word; the host
// draws the closest it has.
// Design: docs/design/views/controls.md#menu-button

/// A named style a `Menu` button's trigger draws under - what `.menuStyle`
/// takes.
///
/// `MenuStyle` is an open protocol as in SwiftUI: the library ships the
/// common kinds, and any style naming a `menuStyleToken` works.
public protocol MenuStyle: Sendable {
    /// The style's token as it crosses to the host: `"automatic"`,
    /// `"borderlessButton"`, `"bordered"`, `"button"`.
    var menuStyleToken: String { get }
}

/// The platform's own button - bordered where buttons are bordered.
public struct DefaultMenuStyle: MenuStyle {
    /// "automatic", as the style crosses to the host.
    public let menuStyleToken = "automatic"

    /// The style.
    public init() {}
}

/// A bare label that opens its menu on a click - no bezel, no button look.
public struct BorderlessButtonMenuStyle: MenuStyle {
    /// "borderlessButton", as the style crosses to the host.
    public let menuStyleToken = "borderlessButton"

    /// The style.
    public init() {}
}

/// A bordered button - the desktop's ordinary menu button.
public struct BorderedButtonMenuStyle: MenuStyle {
    /// "bordered", as the style crosses to the host.
    public let menuStyleToken = "bordered"

    /// The style.
    public init() {}
}

/// A button styled as the buttons around it.
public struct ButtonMenuStyle: MenuStyle {
    /// "button", as the style crosses to the host.
    public let menuStyleToken = "button"

    /// The style.
    public init() {}
}

extension MenuStyle where Self == DefaultMenuStyle {
    /// `.menuStyle(.automatic)`.
    public static var automatic: DefaultMenuStyle { DefaultMenuStyle() }
}

extension MenuStyle where Self == BorderlessButtonMenuStyle {
    /// `.menuStyle(.borderlessButton)`.
    public static var borderlessButton: BorderlessButtonMenuStyle { BorderlessButtonMenuStyle() }
}

extension MenuStyle where Self == BorderedButtonMenuStyle {
    /// `.menuStyle(.bordered)`.
    public static var bordered: BorderedButtonMenuStyle { BorderedButtonMenuStyle() }
}

extension MenuStyle where Self == ButtonMenuStyle {
    /// `.menuStyle(.button)`.
    public static var button: ButtonMenuStyle { ButtonMenuStyle() }
}

/// Whether the button shows the arrow or chevron that says it opens a menu -
/// what `.menuIndicator` takes.
public enum MenuIndicatorVisibility: Int32, Sendable {
    /// Whatever the style wants. The default.
    case automatic = 0

    /// The indicator shown.
    case visible = 1

    /// The indicator kept back.
    case hidden = 2
}

extension MenuIndicatorVisibility: HostRepresentable {}
extension MenuIndicatorVisibility: StateChoice {}
