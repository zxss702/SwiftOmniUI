// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `MenuButtonContract` on a host: a menu button shows its label and opens its menu, drawn in the style and with the
/// indicator the tree gives it.
@_spi(Host) public enum MenuButtonTests: ConformanceFamily {
    public static let name = "MenuButton"

    public static var cases: [ConformanceCase] {
        [
            Aspects.standsAlone("MenuButton"),
            Aspects.holds(MenuButtonContract.menuStyle, on: "MenuButton", "default", then: "bordered"),
            Aspects.holds(MenuButtonContract.menuIndicator, on: "MenuButton", .hidden, then: .visible),
        ]
    }
}
