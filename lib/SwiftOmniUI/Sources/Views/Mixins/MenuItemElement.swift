// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What a toolbar item and a menu entry share: `text`,
/// `icon`, `isDestructive`, `isEnabled` - and `onClicked`, what
/// choosing one does.
///
/// Written on the item, in any order, before or after its own modifiers:
///
///     ToolbarItem("Delete")
///         .icon("trash.png")
///         .isDestructive(true)
///         .onClicked { delete() }
@preconcurrency @MainActor public protocol MenuItemElement: PropertyContainer {}

extension MenuItemElement {
    /// What the item says. Usually given in the initializer instead.
    @_spi(Host) public func text(_ value: String) -> Modified {
        setValue(MenuItemElementContract.text, value)
    }

    /// The picture on it, resolved from the application's image resources.
    @_spi(Host) public func icon(_ value: ImageSource) -> Modified {
        setValue(MenuItemElementContract.icon, value)
    }

    /// Whether the platform draws it as a destructive action. The look only: a
    /// confirmation is still the handler's to put up.
    @_spi(Host) public func isDestructive(_ value: Bool) -> Modified {
        setValue(MenuItemElementContract.isDestructive, value)
    }

    /// Whether it responds to selection. A disabled item stays visible, so the
    /// user still knows the action exists.
    public func disabled(_ value: Bool) -> Modified {
        setValue(MenuItemElementContract.isEnabled, !value)
    }

    /// `isEnabled` from a state, `$x`, inverted as `.disabled` reads it: the
    /// host carries the state, the item enabled where it stands false.
    public func disabled(_ state: Binding<Bool>) -> Modified {
        plain(MenuItemElementContract.isEnabled, by: state.convert { !$0 })
    }
}

extension MenuItemElement where Modified == Self {
    /// What it does - run when the item is chosen, clicked or tapped. A second
    /// `.onClicked` runs beside the first, like every typed event modifier.
    @_spi(Host) public func onClicked(_ handler: @escaping EventHandler) -> Self {
        modified { $0.addHandler(MenuItemElementContract.clicked.token, handler) }
    }
}
